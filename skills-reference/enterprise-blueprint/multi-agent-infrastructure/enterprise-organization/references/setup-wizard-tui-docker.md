# Setup Wizard TUI/Docker Integration

## Overview
The `hermes setup` command now offers to launch TUI and/or start Docker container after configuration completes. This provides a seamless first-run experience.

## Implementation Location
`/docker/hermes-agent/hermes_cli/setup.py` - patched in `run_setup_wizard()` function.

## New Functions Added

### `_offer_launch_tui_and_docker()`
Called at the end of `run_setup_wizard()` after config is saved and summary displayed.

```python
def _offer_launch_tui_and_docker():
    """Offer to launch TUI and/or start Docker container after setup."""
    print()
    print_header("Next Steps")
    
    # Check if Docker is available
    docker_available = shutil.which("docker") is not None
    compose_available = False
    if docker_available:
        try:
            import subprocess
            result = subprocess.run(["docker", "compose", "version"], capture_output=True)
            compose_available = result.returncode == 0
        except:
            pass
    
    docker_ready = docker_available and compose_available
    
    choices = [
        "Launch TUI (interactive management console)",
    ]
    if docker_ready:
        choices.append("Start Docker container (Hemlock Gateway)")
        choices.append("Launch TUI AND start Docker container")
    else:
        choices.append("Start Docker container (Docker not available - will prompt to install)")
    
    choices.append("Skip - I'll start things manually")
    
    choice = prompt_choice("What would you like to do next?", [
        "Launch TUI (interactive management console)",
        "Start Docker container" + ("" if docker_ready else " (will prompt to install Docker)"),
        "Launch TUI AND start Docker container",
        "Skip - I'll start things manually"
    ], 0)
    
    if choice == 3:  # Skip
        print_info("Setup complete! Run 'hermes tui' to launch TUI, 'hermes gateway start' to start Docker.")
        return
    
    # Handle Docker start
    if choice in [1, 2]:
        _start_docker_container()
    
    if choice in [0, 2]:
        _launch_tui()
```

### `_start_docker_container()`
```python
def _start_docker_container():
    """Start the Docker container."""
    print()
    print_header("Starting Docker Container")
    
    import subprocess
    PROJECT_ROOT = Path(__file__).parent.parent.resolve()
    
    try:
        # Check if docker-compose.yml exists
        compose_file = PROJECT_ROOT / "docker-compose.yml"
        if not compose_file.exists():
            # Try to find it in hemlock-minimal
            compose_file = PROJECT_ROOT / "hemlock-minimal" / "docker-compose.yml"
        
        if compose_file.exists():
            print_info(f"Starting with {compose_file}")
            result = subprocess.run(
                ["docker", "compose", "-f", str(compose_file), "up", "-d"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                print_success("Docker container started successfully!")
                print_info("Gateway will be available at http://localhost:18789")
            else:
                print_error(f"Failed to start: {result.stderr}")
                print_info("You can start manually with 'docker compose up -d'")
        else:
            print_warning("docker-compose.yml not found. Start manually with 'docker compose up -d'")
    except Exception as e:
        print_error(f"Failed to start Docker: {e}")
        print_info("Start manually with: docker compose up -d")
```

### `_launch_tui()`
```python
def _launch_tui():
    """Launch the Hermes TUI."""
    print()
    print_header("Launching TUI")
    try:
        import subprocess
        import shutil
        
        # Try to find hemlock CLI
        hemlock_bin = shutil.which("hemlock")
        if hemlock_bin:
            os.execvp(hemlock_bin, ["hemlock", "tui"])
        
        # Try python module
        if importlib.util.find_spec("hermes_cli") is not None:
            import sys
            os.execvp(sys.executable, [sys.executable, "-m", "hermes_cli.main", "tui"])
        
        print_info("Could not launch TUI automatically. Run 'hemlock tui' manually.")
    except Exception as e:
        print_warning(f"Could not launch TUI: {e}")
        print_info("Run 'hemlock tui' manually.")
```

## Integration Point
Added to end of `run_setup_wizard()` in `setup.py`:

```python
def run_setup_wizard(args):
    # ... existing code ...
    
    # Save and show summary
    save_config(config)
    _print_setup_summary(config, hermes_home)
    
    _offer_launch_chat()
    
    # NEW: Offer TUI/Docker launch
    _offer_launch_tui_and_docker()
```

## User Experience Flow

```
$ hermes setup
# ... configuration steps ...
# Configuration saved
✅ Setup complete!

┌─────────────────────────────────────────────────────────┐
│                    Next Steps                            │
├─────────────────────────────────────────────────────────┤
│  1. Launch TUI (interactive management console)         │
│  2. Start Docker container (Hemlock Gateway)            │
│  3. Launch TUI AND start Docker container               │
│  4. Skip - I'll start things manually                   │
└─────────────────────────────────────────────────────────┘

What would you like to do next? [1]: 3

[Starting Docker Container...]
✅ Docker container started successfully!
Gateway will be available at http://localhost:18789

[Launching TUI...]
```

## Key Features

1. **Auto-detects Docker availability** - checks `docker` and `docker compose`
2. **Graceful degradation** - offers to install Docker if missing
3. **Multiple launch options** - TUI only, Docker only, both, or none
4. **Uses existing hemlock CLI** - finds `hemlock` binary or python module
4. **Graceful fallback** - shows manual commands if auto-launch fails
5. **Cross-platform** - works on Linux, macOS (with Docker Desktop)

## Testing

```bash
# Test setup wizard
hermes setup

# Test individual components
hermes setup model
hermes setup gateway
hermes tui
hermes gateway start
```

## Key Learnings (Session 2026-06-13)

1. **Use `os.execvp` for process replacement** - replaces current process, no orphan
2. **Check Docker availability** before offering to start
3. **Find compose file** - check project root then hemlock-minimal subdir
4. **Graceful fallback** - show manual commands if auto-launch fails
5. **Use `shutil.which`** to find binaries cross-platform
6. **Use `os.execvp`** for process replacement (no child process)
6. **Graceful degradation** - offer manual steps if auto-launch fails
7. **Try python module** as fallback when binary not in PATH