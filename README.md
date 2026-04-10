# GDR Automation - Hardware Validation Test Suite

A Windows automation toolkit for validating hardware components on PCs and laptops. Designed to streamline hardware QA testing by automatically running diagnostic checks and generating an HTML report with PASS/FAIL results.

## Features

- Automated hardware diagnostics across multiple categories
- Clearly distinguishes between **auto-testable** items (PASS/FAIL) and **manual** items (human verification required)
- Generates a timestamped **HTML report** upon completion
- Color-coded console output for quick status review

## Test Categories

| Category | Description |
|----------|-------------|
| Audio | Audio services, device detection, driver status |
| Battery | Charge level, AC/DC detection, power plan |
| Display Adapter | GPU detection, driver version, monitor detection, driver signing |
| Video | Edge browser, Movies & TV app, video playback checks |
| Ethernet | Network adapter detection and connectivity |

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later
- Administrator privileges (required for adapter enable/disable tests)

## Usage

Double-click `run_tests.bat` — it will automatically request Administrator privileges, run all tests, and open the HTML report when done.

```
hardware_validation/
├── hw_tests.ps1     # Main test script (PowerShell)
└── run_tests.bat    # Launcher (auto-elevates to Admin)
```

## Report

After each run, an HTML report is saved in the same folder:
```
report_YYYYMMDD_HHmmss.html
```
The report lists every test with its status (PASS / FAIL / WARN / SKIP / MANUAL) and detail notes.
