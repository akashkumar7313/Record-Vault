/**
 * RecordVault — Google Apps Script Backend (15 Columns Only)
 *
 * Headers:
 * 1.  Application No
 * 2.  Name
 * 3.  Name / Father's or Husband's
 * 4.  Relation
 * 5.  Male / Female
 * 6.  Aadhaar Number
 * 7.  Address
 * 8.  Bank Name
 * 9.  Account Number
 * 10. IFSC Code
 * 11. Address Correct
 * 12. Mobile Number Correct
 * 13. Remarks
 * 14. Created At
 * 15. Updated At
 */

var SPREADSHEET_ID = '1-xzBomnHFpclUKpzED7f60Lzo121HtWdwdDxISP9_Nw';
var SHEET_NAME = 'Records';
var CODE_VERSION = 'v15-clean';

var COLUMNS = [
  'Application No',
  'Name',
  "Name / Father's or Husband's",
  'Relation',
  'Male / Female',
  'Aadhaar Number',
  'Address',
  'Bank Name',
  'Account Number',
  'IFSC Code',
  'Address Correct',
  'Mobile Number Correct',
  'Remarks',
  'Created At',
  'Updated At'
];

var AADHAAR_INDEX = 5; // 0-based index of 'Aadhaar Number'


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

  ensure15Columns_(sheet);
  return sheet;
}

/**
 * Enforces exactly the 15 requested columns.
 * Removes any leftover legacy columns and deletes rogue header rows.
 */
function ensure15Columns_(sheet) {
  var lastRow = sheet.getLastRow();
  var lastCol = sheet.getLastColumn();

  if (lastRow === 0 || lastCol === 0) {
    sheet.getRange(1, 1, 1, COLUMNS.length).setNumberFormat('@');
    sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]);
    sheet.setFrozenRows(1);
    return;
  }

  // Ensure row 1 has the exact 15 headers
  sheet.getRange(1, 1, 1, COLUMNS.length).setNumberFormat('@');
  sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]);

  // Remove any surplus columns past column 15
  if (lastCol > COLUMNS.length) {
    sheet.deleteColumns(COLUMNS.length + 1, lastCol - COLUMNS.length);
  }

  // Remove rogue rows that contain old header text like 'aadhaarNumber' or 'fullName'
  var values = sheet.getDataRange().getDisplayValues();
  for (var r = values.length - 1; r >= 1; r--) {
    var firstCell = String(values[r][0] || '').trim();
    var sixthCell = String(values[r][5] || '').trim();
    if (
      firstCell === 'aadhaarNumber' ||
      firstCell === 'id' ||
      sixthCell === 'email' ||
      sixthCell === 'photoFileId'
    ) {
      sheet.deleteRow(r + 1);
    }
  }

  sheet.setFrozenRows(1);
}

function rowToRecord_(row) {
  var rec = {};
  for (var i = 0; i < COLUMNS.length; i++) {
    var colName = COLUMNS[i];
    rec[colName] = row[i] != null ? String(row[i]) : '';
  }

  // Also expose camelCase properties for apps / clients
  rec.applicationNo = rec['Application No'];
  rec.name = rec['Name'];
  rec.fullName = rec['Name'];
  rec.guardianName = rec["Name / Father's or Husband's"];
  rec.fatherName = rec["Name / Father's or Husband's"];
  rec.relation = rec['Relation'];
  rec.gender = String(rec['Male / Female']).toLowerCase();
  rec.aadhaarNumber = cleanDigits_(rec['Aadhaar Number']);
  rec.address = rec['Address'];
  rec.bankName = rec['Bank Name'];
  rec.accountNumber = rec['Account Number'];
  rec.ifscCode = rec['IFSC Code'];
  rec.addressCorrect = rec['Address Correct'];
  rec.mobileNumberCorrect = rec['Mobile Number Correct'];
  rec.remarks = rec['Remarks'];
  rec.createdAt = rec['Created At'];
  rec.updatedAt = rec['Updated At'];

  return rec;
}

function recordToRow_(record, existingRow, aadhaar) {
  var now = new Date().toISOString();

  var appNo = record['Application No'] !== undefined ? record['Application No'] : (record.applicationNo || '');
  var name = record['Name'] !== undefined ? record['Name'] : (record.name || record.fullName || '');
  var guardian = record["Name / Father's or Husband's"] !== undefined ? record["Name / Father's or Husband's"] : (record.guardianName || record.fatherName || '');
  var rel = record['Relation'] !== undefined ? record['Relation'] : (record.relation || '');
  var gen = record['Male / Female'] !== undefined ? record['Male / Female'] : (record.gender || '');
  var aadh = aadhaar || record['Aadhaar Number'] || record.aadhaarNumber || '';
  var addr = record['Address'] !== undefined ? record['Address'] : (record.address || '');
  var bank = record['Bank Name'] !== undefined ? record['Bank Name'] : (record.bankName || '');
  var acc = record['Account Number'] !== undefined ? record['Account Number'] : (record.accountNumber || '');
  var ifsc = record['IFSC Code'] !== undefined ? record['IFSC Code'] : (record.ifscCode || '');
  var addrCorr = record['Address Correct'] !== undefined ? record['Address Correct'] : (record.addressCorrect || '');
  var mobCorr = record['Mobile Number Correct'] !== undefined ? record['Mobile Number Correct'] : (record.mobileNumberCorrect || record.mobileNumber || '');
  var rem = record['Remarks'] !== undefined ? record['Remarks'] : (record.remarks || '');
  var created = record['Created At'] || record.createdAt || (existingRow ? existingRow[13] : '') || now;
  var updated = now;

  return [
    String(appNo != null ? appNo : (existingRow ? existingRow[0] : '')),
    String(name != null ? name : (existingRow ? existingRow[1] : '')),
    String(guardian != null ? guardian : (existingRow ? existingRow[2] : '')),
    String(rel != null ? rel : (existingRow ? existingRow[3] : '')),
    String(gen != null ? gen : (existingRow ? existingRow[4] : '')),
    cleanDigits_(aadh != null ? aadh : (existingRow ? existingRow[5] : '')),
    String(addr != null ? addr : (existingRow ? existingRow[6] : '')),
    String(bank != null ? bank : (existingRow ? existingRow[7] : '')),
    String(acc != null ? acc : (existingRow ? existingRow[8] : '')),
    String(ifsc != null ? ifsc : (existingRow ? existingRow[9] : '')).toUpperCase(),
    String(addrCorr != null ? addrCorr : (existingRow ? existingRow[10] : '')),
    String(mobCorr != null ? mobCorr : (existingRow ? existingRow[11] : '')),
    String(rem != null ? rem : (existingRow ? existingRow[12] : '')),
    String(created),
    String(updated)
  ];
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
      if (reqAppNo && String(rec['Application No']).trim() === reqAppNo) {
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
      var reqAadhaar = cleanDigits_(body.aadhaarNumber || body.aadhaar || record['Aadhaar Number'] || record.aadhaarNumber);
      var reqAppNo = String(body.applicationNo || body.appNo || record['Application No'] || record.applicationNo || '').trim();

      var all = [];
      for (var r = 1; r < values.length; r++) {
        var row = values[r];
        if (!row.some(function (v) { return String(v || '').trim() !== ''; })) continue;

        var rec = rowToRecord_(row);

        if (reqAadhaar && rec.aadhaarNumber === reqAadhaar) {
          return jsonResponse({ success: true, version: CODE_VERSION, action: 'read', data: rec });
        }
        if (reqAppNo && String(rec['Application No']).trim() === reqAppNo) {
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
        return errorResponse_('Column "' + body.columnName + '" is invalid. Must be one of the 15 headers.');
      }

      var cell = sheet.getRange(rowIndex, colIdx);
      cell.setNumberFormat('@');
      cell.setValue(String(body.newValue != null ? body.newValue : ''));

      // Update 'Updated At' (column 15)
      sheet.getRange(rowIndex, 15).setValue(new Date().toISOString());
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
 * - Resets Row 1 to ONLY the 15 headers.
 * - Deletes any extra columns past column 15.
 * - Deletes any extra rows containing old headers.
 */
function cleanSheetNow() {
  var sheet = getSheet_();
  ensure15Columns_(sheet);

  var result = {
    success: true,
    message: 'Sheet cleaned! Exactly 15 columns exist now.',
    headers: COLUMNS,
    totalRows: sheet.getLastRow()
  };

  Logger.log(JSON.stringify(result, null, 2));
  return result;
}
