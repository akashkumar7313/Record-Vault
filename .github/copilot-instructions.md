# RecordVault AI Agent Guidelines

This document outlines essential knowledge for AI coding agents working on the RecordVault codebase. It focuses on architecture, critical workflows, conventions, and integration points to facilitate immediate productivity.

## 1. Architecture Overview

RecordVault is a vanilla JavaScript client-side application located in `web-vanilla/`. It interacts with a Google Apps Script backend (`tool/apps_script/Code.gs`) that serves as an API to Google Sheets.

*   **Frontend (`web-vanilla/app.js`):** Manages UI rendering, user interactions, and local application state.
*   **Backend (`tool/apps_script/Code.gs`):** Handles data storage and retrieval from Google Sheets, exposed via a web app URL (the `DEFAULT_ENDPOINT`).
*   **Data Flow:** The frontend communicates with the Apps Script backend via `fetch` requests, sending and receiving JSON data.

## 2. Critical Developer Workflows

*   **Data Synchronization:**
    *   `syncNow(auto)`: Fetches the latest records from the Google Sheet and updates the local application state. This function includes retry logic and updates the UI based on sync status.
    *   Records are filtered and sorted using `filteredRecords()` and always sorted by `updatedAt` value.
*   **Record Management (CRUD):**
    *   `openForm(existing)`: Opens a modal form for adding new records or editing existing ones.
    *   `Api.addRecord(record)`: Sends a new record to the Apps Script backend.
    *   `Api.updateRecord(record)`: Sends updated record data to the Apps Script backend.
    *   `deleteRecordFlow(aadhaar)`: Initiates the process to delete a record, including a confirmation dialog and calling `Api.deleteRecord`.
*   **UI Rendering:**
    *   `render()`: The main rendering function, called when the application state (`S`) changes. It delegates to specific rendering functions for different tabs (`renderDashboard`, `renderRecords`, `renderSettings`).
    *   `openSheet()`: Manages the display of modal sheets/dialogs for forms, details, and confirmations.

## 3. Project-Specific Conventions and Patterns

*   **Global State Management:** The `S` object (`web-vanilla/app.js`, line 28) stores the entire application's mutable state (e.g., `S.tab`, `S.records`, `S.loading`, `S.error`). All UI updates are triggered by changes to this object.
*   **API Abstraction:** All communication with the Google Apps Script backend is encapsulated within the `Api` object (`web-vanilla/app.js`, line 157). This includes `send`, `fetchRecords`, `addRecord`, `updateRecord`, and `deleteRecord`.
*   **Data Transformation:**
    *   `normalizeRecord(item)`: Converts raw data received from the backend into the application's internal record format.
    *   `toRemoteJson(record)`: Transforms the internal record format into the structure expected by the Google Apps Script for write operations.
*   **Input Validation:** The `Validators` object (`web-vanilla/app.js`, line 108) defines validation rules for various input fields used in record forms.
*   **DOM Manipulation:** The application directly manipulates the DOM using `document.getElementById` (aliased as `el`) and `innerHTML` to update the UI.

## 4. Integration Points and External Dependencies

*   **Google Apps Script Backend:** The core integration. The `endpoint()` function (`web-vanilla/app.js`, line 42) determines the URL for the Apps Script API, which can be overridden by local storage or URL parameters.
*   **Local Storage:** Used for persisting user preferences like `rv_endpoint` and `rv_theme`.
*   **Navigator.onLine API:** Used to detect network connectivity changes and update the UI accordingly (`window.addEventListener("online")`, `window.addEventListener("offline")`).
*   **XLSX Library:** The `buildWorkbookBlob` function (`web-vanilla/app.js`, line 1184) conditionally uses a global `window.XLSX` object for Excel export. If this is not present, it defaults to CSV export. Assume `XLSX` is loaded via a separate script.
*   **Google Material Symbols:** Used for all icons in the application's UI.