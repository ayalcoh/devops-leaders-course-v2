import os
import multiprocessing
import time
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import requests
from dotenv import load_dotenv


load_dotenv()
app = FastAPI()

# Mount static files (for CSS/JS)
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Global variables for managing CPU stress test processes
cpu_stress_processes = []  # List to store process objects
global_iterations = None  # Shared counter for iterations across workers
stop_flag = None  # Shared flag used to signal processes to stop
cpu_stress_end_time = None
cpu_stress_status_data = {}  # To hold status metadata (running, start_time, etc.)


def cpu_worker(end_time, load, cycle_time, global_iterations, stop_flag):
    """
    Worker function that simulates CPU load.

    It busy-loops for a fraction of each cycle determined by 'load' and then sleeps.
    """
    busy_time = cycle_time * (load / 100)
    idle_time = cycle_time - busy_time
    while time.time() < end_time and not stop_flag.value:
        start_busy = time.time()
        # Busy loop: performing heavy computation
        while time.time() - start_busy < busy_time and not stop_flag.value:
            _ = sum(i * i for i in range(10000))
            with global_iterations.get_lock():
                global_iterations.value += 1
        if idle_time > 0 and not stop_flag.value:
            time.sleep(idle_time)


@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Render the homepage, passing the stress-test feature flag."""
    stress_test_enabled = os.environ.get("STRESS_TEST_FLAG", "").lower() == "true"
    return templates.TemplateResponse(
        "index.html", {"request": request, "stress_test_enabled": stress_test_enabled}
    )


@app.get("/weather", response_class=JSONResponse)
async def weather(location: str):
    """
    Retrieves weather info for the provided location using wttr.in.
    """
    url = f"http://wttr.in/{location}?format=j1"
    response = requests.get(url)
    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code, detail="Weather data not found"
        )
    data = response.json()
    try:
        current = data["current_condition"][0]
        nearest_area = data["nearest_area"][0] if data.get("nearest_area") else {}
    except (KeyError, IndexError):
        raise HTTPException(
            status_code=500, detail="Unexpected response format from weather service"
        )
    weather_data = {
        "location": nearest_area.get("areaName", [{}])[0].get("value", location),
        "temperature": current.get("temp_C"),
        "description": current.get("weatherDesc", [{}])[0].get("value"),
        "lat": float(nearest_area.get("latitude", 0)),
        "lon": float(nearest_area.get("longitude", 0)),
    }
    return JSONResponse(content=weather_data)


@app.get("/start_cpu_stress", response_class=JSONResponse)
async def start_cpu_stress(duration: int = 10, load: int = 100):
    """
    Starts a CPU stress test for a given duration (in seconds) with a controllable load.

    This endpoint is protected by the STRESS_TEST_FLAG feature flag.
    """
    if os.environ.get("STRESS_TEST_FLAG", "").lower() != "true":
        raise HTTPException(
            status_code=403, detail="CPU stress test feature is disabled"
        )

    global cpu_stress_processes, global_iterations, stop_flag, cpu_stress_end_time
    global cpu_stress_status_data
    if duration <= 0 or not (0 <= load <= 100):
        raise HTTPException(
            status_code=400, detail="Invalid duration or load parameter"
        )

    # Stop any existing stress test first.
    if cpu_stress_processes:
        for p in cpu_stress_processes:
            p.terminate()
        cpu_stress_processes = []

    # Setup shared variables.
    global_iterations = multiprocessing.Value("i", 0)
    stop_flag = multiprocessing.Value("b", False)
    cpu_stress_end_time = time.time() + duration

    # Use one process per available CPU core.
    workers = os.cpu_count() or 1
    cycle_time = 0.1  # seconds per cycle

    # Update our status dictionary.
    cpu_stress_status_data = {
        "running": True,
        "start_time": time.time(),
        "duration": duration,
        "end_time": cpu_stress_end_time,
        "load": load,
        "workers": workers,
    }

    # Spawn the worker processes.
    for _ in range(workers):
        p = multiprocessing.Process(
            target=cpu_worker,
            args=(cpu_stress_end_time, load, cycle_time, global_iterations, stop_flag),
        )
        p.start()
        cpu_stress_processes.append(p)

    return JSONResponse(
        content={
            "message": "CPU stress test started",
            "duration": duration,
            "load": load,
            "workers": workers,
        }
    )


@app.get("/stop_cpu_stress", response_class=JSONResponse)
async def stop_cpu_stress():
    """
    Stops the ongoing CPU stress test.

    This endpoint is protected by the STRESS_TEST_FLAG feature flag.
    """
    if os.environ.get("STRESS_TEST_FLAG", "").lower() != "true":
        raise HTTPException(
            status_code=403, detail="CPU stress test feature is disabled"
        )

    global stop_flag, cpu_stress_status_data, cpu_stress_processes
    if stop_flag is not None:
        stop_flag.value = True
    for p in cpu_stress_processes:
        p.join(timeout=1)
    cpu_stress_status_data["running"] = False
    cpu_stress_processes = []
    return JSONResponse(content={"message": "CPU stress test stopped"})


@app.get("/stress_status", response_class=JSONResponse)
async def stress_status():
    """
    Returns the current status of the CPU stress test.

    This endpoint is protected by the STRESS_TEST_FLAG feature flag.
    """
    if os.environ.get("STRESS_TEST_FLAG", "").lower() != "true":
        raise HTTPException(
            status_code=403, detail="CPU stress test feature is disabled"
        )

    global cpu_stress_status_data, global_iterations
    now = time.time()
    if cpu_stress_status_data.get("running", False):
        remaining = max(0, cpu_stress_status_data["end_time"] - now)
    else:
        remaining = 0
    iterations = global_iterations.value if global_iterations is not None else 0
    if now >= cpu_stress_status_data.get("end_time", 0):
        cpu_stress_status_data["running"] = False
    return JSONResponse(
        content={
            "running": cpu_stress_status_data.get("running", False),
            "remaining_seconds": int(remaining),
            "iterations": iterations,
        }
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
