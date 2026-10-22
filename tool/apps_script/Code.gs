/**
 * RecordVault — Google Apps Script Backend
 *
 * Headers (exact order matches the app + Google Sheet):
 * 1.  S.R
 * 2.  Application_No
 * 3.  AADHAR NUMBER
 * 4.  MOBILE NUMBER CORECT
 * 5.  NAME
 * 6.  NAME HINDI
 * 7.  NAME PROPER
 * 8.  AYA NAME
 * 9.  F/H NAME
 * 10. NAME HINDI          (second, duplicate header — kept positionally)
 * 11. F/H NAME PROPER
 * 12. RELETION
 * 13. FULE NAME PROPER
 * 14. MALE / FEMALE
 * 15. MOTHER NAME
 * 16. ADDRESS
 * 17. WARD N0
 * 18. HOUSE N0
 * 19. BILL NO
 * 20. BILL DATE
 * 21. SAMPATTI CODE
 * 22. BANK NAME
 * 23. ACCOUNNT NUMBER
 * 24. IFSC CODE
 * 25. THOUGHT
 * 26. ADDRES CORECT
 * 27. Created At
 * 28. Updated At
 */

var SPREADSHEET_ID = '1-xzBomnHFpclUKpzED7f60Lzo121HtWdwdDxISP9_Nw';
var SHEET_NAME = 'Records';
var CODE_VERSION = 'v28-new';

var COLUMNS = [
  'S.R',
  'Application_No',
  'AADHAR NUMBER',
  'MOBILE NUMBER CORECT',
  'NAME',
  'NAME HINDI',
  'NAME PROPER',
  'AYA NAME',
  'F/H NAME',
  'NAME HINDI',
  'F/H NAME PROPER',
  'RELETION',
  'FULE NAME PROPER',
  'MALE / FEMALE',
  'MOTHER NAME',
  'ADDRESS',
  'WARD N0',
  'HOUSE N0',
  'BILL NO',
  'BILL DATE',
  'SAMPATTI CODE',
  'BANK NAME',
  'ACCOUNNT NUMBER',
  'IFSC CODE',
  'THOUGHT',
  'ADDRES CORECT',
  'Created At',
  'Updated At'
];

// Unique internal key for each column, in the same order as COLUMNS.
// Needed because 'NAME HINDI' appears twice.
var KEYS = [
  'srNo',
  'applicationNo',
  'aadhaarNumber',
  'mobileNumberCorrect',
  'name',
  'nameHindi',
  'nameProper',
  'ayaName',
  'fatherHusbandName',
  'nameHindi2',
  'fatherHusbandNameProper',
  'relation',
  'fullNameProper',
  'gender',
  'motherName',
  'address',
  'wardNo',
  'houseNo',
  'billNo',
  'billDate',
  'sampattiCode',
  'bankName',
  'accountNumber',
  'ifscCode',
  'thought',
  'addressCorrect',
  'createdAt',
  'updatedAt'
];

var AADHAAR_INDEX = 2;               // 0-based index of 'AADHAR NUMBER'
var IFSC_INDEX = 23;                 // 0-based index of 'IFSC CODE'
var CREATED_INDEX = COLUMNS.length - 2;
var UPDATED_INDEX = COLUMNS.length - 1;

  
/* -------------------- RESPONSE HELPERS -------------------- */

function jsonResponse(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

function errorResponse_(message) {
  return jsonResponse({
    success: false,
    version: CODE_VERSION,
    message: String(message || 'Unknown error')
  });
}

function cleanDigits_(val) {
  return String(val == null ? '' : val).replace(/[^0-9]/g, '');
}


/* -------------------- SPREADSHEET HELPERS -------------------- */

function getSpreadsheet_() {
  try {
    var active = SpreadsheetApp.getActiveSpreadsheet();
    if (active) return active;
  } catch (e) {}

  return SpreadsheetApp.openById(SPREADSHEET_ID);
}

function getSheet_() {
  var ss = getSpreadsheet_();
  var sheet = ss.getSheetByName(SHEET_NAME);

  if (!sheet) {
    var allSheets = ss.getSheets();
    for (var s = 0; s < allSheets.length; s++) {
      if (allSheets[s].getLastRow() > 0) {
        sheet = allSheets[s];
        break;
      }
    }
    if (!sheet) {
      sheet = ss.insertSheet(SHEET_NAME);
    }
  }

  ensureColumns_(sheet);
  return sheet;
}

/**
 * Enforces exactly the requested columns.
 * Removes any leftover legacy columns and deletes rogue header rows.
 */
function ensureColumns_(sheet) {
  var lastRow = sheet.getLastRow();
  var lastCol = sheet.getLastColumn();

  if (lastRow === 0 || lastCol === 0) {
    sheet.getRange(1, 1, 1, COLUMNS.length).setNumberFormat('@');
    sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]);
    sheet.setFrozenRows(1);
    return;
  }

  // Ensure row 1 has the exact headers
  sheet.getRange(1, 1, 1, COLUMNS.length).setNumberFormat('@');
  sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]);

  // Remove any surplus columns past the required count
  if (lastCol > COLUMNS.length) {
    sheet.deleteColumns(COLUMNS.length + 1, lastCol - COLUMNS.length);
  }

  // Remove rogue rows that contain old header text like 'aadhaarNumber' or 'id'
  var values = sheet.getDataRange().getDisplayValues();
  for (var r = values.length - 1; r >= 1; r--) {
    var firstCell = String(values[r][0] || '').trim();
    if (firstCell === 'aadhaarNumber' || firstCell === 'id') {
      sheet.deleteRow(r + 1);
    }
  }

  sheet.setFrozenRows(1);
}

function rowToRecord_(row) {
  var rec = {};
  for (var i = 0; i < COLUMNS.length; i++) {
    var value = row[i] != null ? String(row[i]) : '';
    rec[KEYS[i]] = value;
    // Also expose the sheet header for clients that read by header name.
    // Skipped when a header repeats (the second 'NAME HINDI'), so the alias
    // always refers to the first occurrence.
    if (rec[COLUMNS[i]] === undefined) rec[COLUMNS[i]] = value;
  }

  rec.aadhaarNumber = cleanDigits_(rec.aadhaarNumber);
  rec.gender = String(rec.gender || '').toLowerCase();

  return rec;
}

function recordToRow_(record, existingRow, aadhaar) {
  var now = new Date().toISOString();
  var row = [];

  for (var i = 0; i < COLUMNS.length; i++) {
    var key = KEYS[i];
    var value;
    if (record[key] !== undefined) {
      value = record[key];
    } else if (key !== 'nameHindi2' && record[COLUMNS[i]] !== undefined) {
      // Header-keyed payloads are accepted for every column except the
      // duplicate 'NAME HINDI' (which is addressed by its unique key).
      value = record[COLUMNS[i]];
    } else {
      value = existingRow ? existingRow[i] : '';
    }
    row.push(value);
  }

  row[AADHAAR_INDEX] = cleanDigits_(aadhaar || row[AADHAAR_INDEX] || '');
  row[IFSC_INDEX] = String(row[IFSC_INDEX] != null ? row[IFSC_INDEX] : '').toUpperCase();

  var created = row[CREATED_INDEX] || (existingRow ? existingRow[CREATED_INDEX] : '') || now;
  var updated = row[UPDATED_INDEX] || now;
  row[CREATED_INDEX] = String(created);
  row[UPDATED_INDEX] = String(updated);

  for (var j = 0; j < row.length; j++) {
    row[j] = String(row[j] != null ? row[j] : '');
  }

  return row;
}


/* -------------------- READ (GET) -------------------- */

function doGet(e) {
  var lock = LockService.getScriptLock();

  try {
    lock.waitLock(30000);

    var sheet = getSheet_();
    var values = sheet.getDataRange().getDisplayValues();

    if (values.length <= 1) {
      return jsonResponse({ success: true, version: CODE_VERSION, data: [] });
    }

    var params = (e && e.parameter) || {};
    var reqAadhaar = cleanDigits_(params.aadhaarNumber || params.aadhaar);
    var reqAppNo = String(params.applicationNo || params.appNo || '').trim();

    var data = [];

    for (var r = 1; r < values.length; r++) {
      var row = values[r];
      var hasAny = row.some(function (v) { return String(v || '').trim() !== ''; });
      if (!hasAny) continue;

      var rec = rowToRecord_(row);

      // Single query by Aadhaar
      if (reqAadhaar && rec.aadhaarNumber === reqAadhaar) {
        return jsonResponse({ success: true, version: CODE_VERSION, data: rec });
      }

      // Single query by Application No
      if (reqAppNo && String(rec.applicationNo).trim() === reqAppNo) {
        return jsonResponse({ success: true, version: CODE_VERSION, data: rec });
      }

      data.push(rec);
    }

    if (reqAadhaar || reqAppNo) {
      return errorResponse_('Record not found');
    }

    return jsonResponse({ success: true, version: CODE_VERSION, data: data });

  } catch (error) {
    return errorResponse_(error.message);

  } finally {
    try { lock.releaseLock(); } catch (i) {}
  }
}


/* -------------------- CRUD (POST) -------------------- */

function doPost(e) {
  if (!e || !e.postData || !e.postData.contents) {
    return errorResponse_('Empty request body');
  }

  var body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return errorResponse_('Invalid JSON');
  }

  var action = String(body.action || '').toLowerCase().trim();
  var record = body.record || body.data || body;
  if (typeof record !== 'object' || Array.isArray(record)) record = {};

  var lock = LockService.getScriptLock();

  try {
    lock.waitLock(30000);

    var sheet = getSheet_();
    var values = sheet.getDataRange().getDisplayValues();

    /* 1. READ ALL OR SINGLE */
    if (action === 'read' || action === 'get' || action === 'fetch' || action === 'list') {
      var reqAadhaar = cleanDigits_(body.aadhaarNumber || body.aadhaar || record['AADHAR NUMBER'] || record['Aadhaar Number'] || record.aadhaarNumber);
      var reqAppNo = String(body.applicationNo || body.appNo || record['Application_No'] || record['Application No'] || record.applicationNo || '').trim();

      var all = [];
      for (var r = 1; r < values.length; r++) {
        var row = values[r];
        if (!row.some(function (v) { return String(v || '').trim() !== ''; })) continue;

        var rec = rowToRecord_(row);

        if (reqAadhaar && rec.aadhaarNumber === reqAadhaar) {
          return jsonResponse({ success: true, version: CODE_VERSION, action: 'read', data: rec });
        }
        if (reqAppNo && String(rec.applicationNo).trim() === reqAppNo) {
          return jsonResponse({ success: true, version: CODE_VERSION, action: 'read', data: rec });
        }

        all.push(rec);
      }

      if (reqAadhaar || reqAppNo) {
        return errorResponse_('Record not found');
      }

      return jsonResponse({ success: true, version: CODE_VERSION, action: 'read', data: all });
    }

    /* Identify target row by Aadhaar */
    var targetAadhaar = cleanDigits_(
      body.aadhaarNumber ||
      body.aadhaar ||
      record['AADHAR NUMBER'] ||
      record['Aadhaar Number'] ||
      record.aadhaarNumber
    );

    var rowIndex = -1;
    if (targetAadhaar.length === 12) {
      for (var r2 = 1; r2 < values.length; r2++) {
        if (cleanDigits_(values[r2][AADHAAR_INDEX]) === targetAadhaar) {
          rowIndex = r2 + 1; // 1-based row index
          break;
        }
      }
    }

    /* 2. DELETE */
    if (action === 'delete' || action === 'remove') {
      if (rowIndex > 0) {
        sheet.deleteRow(rowIndex);
        SpreadsheetApp.flush();
        return jsonResponse({
          success: true,
          version: CODE_VERSION,
          action: 'deleted',
          aadhaarNumber: targetAadhaar
        });
      }
      return errorResponse_('Record not found to delete');
    }

    /* 3. UPDATE SINGLE COLUMN */
    if (action === 'update_column') {
      if (!body.columnName || body.newValue === undefined) {
        return errorResponse_('columnName and newValue are required');
      }
      if (rowIndex < 0) {
        return errorResponse_('Record not found to update column');
      }

      var colIdx = -1;
      for (var c = 0; c < COLUMNS.length; c++) {
        if (COLUMNS[c].toLowerCase() === String(body.columnName).toLowerCase().trim()) {
          colIdx = c + 1;
          break;
        }
      }
      if (colIdx < 0) {
        return errorResponse_('Column "' + body.columnName + '" is invalid. Must be one of the ' + COLUMNS.length + ' headers.');
      }

      var cell = sheet.getRange(rowIndex, colIdx);
      cell.setNumberFormat('@');
      cell.setValue(String(body.newValue != null ? body.newValue : ''));

      // Update 'Updated At' (last column)
      sheet.getRange(rowIndex, UPDATED_INDEX + 1).setValue(new Date().toISOString());
      SpreadsheetApp.flush();

      return jsonResponse({
        success: true,
        version: CODE_VERSION,
        action: 'column_updated',
        columnName: COLUMNS[colIdx - 1],
        aadhaarNumber: targetAadhaar,
        newValue: body.newValue
      });
    }

    /* 4. CREATE / ADD / UPSERT */
    if (action === 'add' || action === 'create' || action === 'upsert' || action === 'insert') {
      if (targetAadhaar.length !== 12) {
        return errorResponse_('A valid 12-digit Aadhaar number is required');
      }

      var existing = rowIndex > 0 ? values[rowIndex - 1] : null;
      var newRow = recordToRow_(record, existing, targetAadhaar);

      if (rowIndex > 0) {
        var range = sheet.getRange(rowIndex, 1, 1, COLUMNS.length);
        range.setNumberFormat('@');
        range.setValues([newRow]);
      } else {
        var nextRow = sheet.getLastRow() + 1;
        var appendRange = sheet.getRange(nextRow, 1, 1, COLUMNS.length);
        appendRange.setNumberFormat('@');
        appendRange.setValues([newRow]);
      }

      SpreadsheetApp.flush();

      return jsonResponse({
        success: true,
        version: CODE_VERSION,
        action: rowIndex > 0 ? 'updated' : 'added',
        aadhaarNumber: targetAadhaar,
        data: rowToRecord_(newRow)
      });
    }

    /* 5. UPDATE FULL RECORD */
    if (action === 'update' || action === 'edit') {
      if (targetAadhaar.length !== 12) {
        return errorResponse_('A valid 12-digit Aadhaar number is required to update');
      }
      if (rowIndex < 0) {
        return errorResponse_('Record not found to update');
      }

      var existingRowData = values[rowIndex - 1];
      var updatedRow = recordToRow_(record, existingRowData, targetAadhaar);

      var updateRange = sheet.getRange(rowIndex, 1, 1, COLUMNS.length);
      updateRange.setNumberFormat('@');
      updateRange.setValues([updatedRow]);

      SpreadsheetApp.flush();

      return jsonResponse({
        success: true,
        version: CODE_VERSION,
        action: 'updated',
        aadhaarNumber: targetAadhaar,
        data: rowToRecord_(updatedRow)
      });
    }

    return errorResponse_('Unsupported action: ' + action);

  } catch (error) {
    return errorResponse_(error.message);

  } finally {
    try { lock.releaseLock(); } catch (i) {}
  }
}


/* -------------------- ONE-CLICK CLEANUP TOOL -------------------- */

/**
 * Run this function from the Apps Script editor to instantly clean your sheet:
 * - Resets Row 1 to ONLY the required headers.
 * - Deletes any extra columns past the last required column.
 * - Deletes any extra rows containing old headers.
 */
function cleanSheetNow() {
  var sheet = getSheet_();
  ensureColumns_(sheet);

  var result = {
    success: true,
    message: 'Sheet cleaned! Exactly ' + COLUMNS.length + ' columns exist now.',
    headers: COLUMNS,
    totalRows: sheet.getLastRow()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}
