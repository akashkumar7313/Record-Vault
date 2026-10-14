/**
 * RecordVault — Google Apps Script Web App backend
 *
 * DEPLOY
 * ------
 *   Deploy → Manage deployments → edit (pencil) → Version: New version → Deploy.
 *   Execute as: Me  |  Who has access: Anyone.
 *
 * API
 * ---
 *   GET  : { "success": true, "data": [ ... ] }
 *   POST : { "action": "add" | "update" | "delete", "record": { ... } }
 *          → { "success": true, "action": "...", "aadhaarNumber": "...",
 *              "photoFileId": "<driveFileId|''>" }
 *          → { "success": false, "message": "..." } on error
 *
 * Records are matched on the 12-digit Aadhaar number, so `add` is an UPSERT.
 * Retrying a request can never create a duplicate row.
 *
 * If `record.photoBase64` is present, the image is uploaded to Google Drive and
 * its file id is saved in the `photoFileId` column.
 */

var SPREADSHEET_ID = '1-xzBomnHFpclUKpzED7f60Lzo121HtWdwdDxISP9_Nw';
var SHEET_NAME = 'Records';
var PHOTO_FOLDER_NAME = 'RecordVault Photos';
// Shown by doGet so you can confirm which version is deployed.
var CODE_VERSION = 'aadhaar-v2';

var COLUMNS = [
  'aadhaarNumber',
  'fullName',
  'fatherName',
  'motherName',
  'mobileNumber',
  'email',
  'address',
  'dateOfBirth',
  'gender',
  'photoFileId',
  'createdAt',
  'updatedAt'
];

// Old / misspelled header names (lower-case) that get upgraded automatically.
var HEADER_ALIASES = {
  'id': 'aadhaarNumber',
  'recordid': 'aadhaarNumber',
  'aadhaar': 'aadhaarNumber',
  'aadhar': 'aadhaarNumber',
  'aadhaar_no': 'aadhaarNumber',
  'aadhar_no': 'aadhaarNumber',
  'aadhaarno': 'aadhaarNumber',
  'aadharno': 'aadhaarNumber',
  'aadhaar_number': 'aadhaarNumber',
  'aadhaarnumber': 'aadhaarNumber',
  'aadhar number': 'aadhaarNumber',
  'aadhaar number': 'aadhaarNumber',
  'photo_file_id': 'photoFileId',
  'photofileid': 'photoFileId'
};

function getSpreadsheet_() {
  return SPREADSHEET_ID
    ? SpreadsheetApp.openById(SPREADSHEET_ID)
    : SpreadsheetApp.getActiveSpreadsheet();
}

function getSheet_() {
  var ss = getSpreadsheet_();
  var sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
  }
  ensureHeader_(sheet);
  return sheet;
}

function ensureHeader_(sheet) {
  var lastRow = sheet.getLastRow();
  var lastCol = sheet.getLastColumn();
  if (lastRow === 0 || lastCol === 0) {
    sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]);
    return;
  }

  var header = sheet.getRange(1, 1, 1, lastCol).getValues()[0];
  var bodyRows = lastRow > 1 ? lastRow - 1 : 0;
  var body = bodyRows > 0
    ? sheet.getRange(2, 1, bodyRows, lastCol).getValues()
    : [];

  // Map each existing header cell to its canonical column name via aliases.
  var canon = header.map(function (cell) {
    var key = String(cell).trim();
    if (key === '') return '';
    var alias = HEADER_ALIASES[key.toLowerCase()];
    return alias ? alias : key;
  });

  // When a name appears in several columns (e.g. legacy "aadharNo" plus a
  // newer "aadhaarNumber"), keep the one that actually holds data.
  var chosen = {};
  for (var i = 0; i < canon.length; i++) {
    var name = String(canon[i]).trim();
    if (name === '') continue;
    if (chosen[name] === undefined) {
      chosen[name] = i;
    } else if (!columnHasData_(body, chosen[name]) && columnHasData_(body, i)) {
      chosen[name] = i;
    }
  }

  // Final order: match COLUMNS (so aadhaarNumber is first), then any extras.
  var order = COLUMNS.slice();
  for (var i = 0; i < canon.length; i++) {
    var name = String(canon[i]).trim();
    if (name !== '' && order.indexOf(name) === -1) order.push(name);
  }

  // Project the existing data onto the canonical column order.
  var newBody = body.map(function (row) {
    return order.map(function (name) {
      var src = chosen[name];
      return src === undefined ? '' : row[src];
    });
  });

  if (lastCol > order.length) {
    sheet.deleteColumns(order.length + 1, lastCol - order.length);
  }
  sheet.getRange(1, 1, 1, order.length).setValues([order]);
  if (newBody.length > 0) {
    sheet.getRange(2, 1, newBody.length, order.length).setValues(newBody);
  }
}

function columnHasData_(body, index) {
  for (var r = 0; r < body.length; r++) {
    var value = body[r][index];
    if (value !== '' && value !== null && value !== undefined) return true;
  }
  return false;
}


/** Keeps digits only, so "1234 5678 9012" matches "123456789012". */
function normaliseAadhaar_(value) {
  return String(value == null ? '' : value).replace(/[^0-9]/g, '');
}

function jsonResponse(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet() {
  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var sheet = getSheet_();
    var values = sheet.getDataRange().getValues();
    if (values.length <= 1) {
      return jsonResponse({ success: true, version: CODE_VERSION, data: [] });
    }
    var header = values[0];
    var data = [];
    for (var r = 1; r < values.length; r++) {
      var row = values[r];
      var record = {};
      for (var c = 0; c < header.length; c++) {
        record[header[c]] = row[c];
      }
      // Only 12-digit Aadhaar rows are valid; drop legacy UUID rows.
      var aadhaar = normaliseAadhaar_(record.aadhaarNumber);
      if (aadhaar.length !== 12) continue;
      record.aadhaarNumber = aadhaar;
      data.push(record);
    }
    return jsonResponse({ success: true, version: CODE_VERSION, data: data });
  } catch (error) {
    return jsonResponse({ success: false, message: error.message });
  } finally {
    lock.releaseLock();
  }
}

function doPost(e) {
  if (!e || !e.postData || !e.postData.contents) {
    return jsonResponse({ success: false, message: 'Empty request body' });
  }

  var body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (error) {
    return jsonResponse({ success: false, message: 'Invalid JSON body' });
  }

  var action = String(body.action || '').toLowerCase();
  var record = body.record || {};
  var aadhaar = normaliseAadhaar_(record.aadhaarNumber);

  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var sheet = getSheet_();
    var values = sheet.getDataRange().getValues();
    var header = values[0];
    var aadhaarIndex = header.indexOf('aadhaarNumber');

    var rowIndex = -1;
    if (aadhaar) {
      for (var r = 1; r < values.length; r++) {
        if (normaliseAadhaar_(values[r][aadhaarIndex]) === aadhaar) {
          rowIndex = r + 1; // 1-based sheet row
          break;
        }
      }
    }

    if (action === 'delete') {
      if (!aadhaar) {
        return jsonResponse({ success: false, message: 'Missing aadhaarNumber' });
      }
      if (rowIndex > 0) {
        trashPhoto_(values[rowIndex - 1][header.indexOf('photoFileId')]);
        sheet.deleteRow(rowIndex);
      }
      // Idempotent: deleting something already gone is still a success.
      return jsonResponse({
        success: true,
        action: 'deleted',
        aadhaarNumber: aadhaar,
        photoFileId: ''
      });
    }

    if (action === 'add' || action === 'upsert' || action === 'update') {
      if (aadhaar.length !== 12) {
        return jsonResponse({ success: false, message: 'Invalid Aadhaar number' });
      }
      if (action === 'update' && rowIndex <= 0) {
        // Nothing to update yet → fall back to insert so data is never lost.
        rowIndex = -1;
      }
      var photoFileId = rowIndex > 0
        ? writeRow_(sheet, header, rowIndex, record, aadhaar)
        : appendRow_(sheet, header, record, aadhaar);
      return jsonResponse({
        success: true,
        action: rowIndex > 0 ? 'updated' : 'added',
        aadhaarNumber: aadhaar,
        photoFileId: photoFileId || ''
      });
    }

    return jsonResponse({ success: false, message: 'Unsupported action: ' + action });
  } catch (error) {
    return jsonResponse({ success: false, message: error.message });
  } finally {
    lock.releaseLock();
  }
}

function buildRow_(header, record, existingRow, aadhaar) {
  var row = header.map(function (key, index) {
    if (key === 'aadhaarNumber') return aadhaar;
    if (record[key] !== undefined && record[key] !== null && record[key] !== '') {
      return record[key];
    }
    return existingRow ? existingRow[index] : '';
  });

  var photoIndex = header.indexOf('photoFileId');
  if (record.photoBase64) {
    var fileId = uploadPhoto_(aadhaar, record.photoBase64);
    if (fileId) {
      row[photoIndex] = fileId;
    }
  }
  if (photoIndex >= 0) {
    row[photoIndex] = row[photoIndex] || '';
  }
  return { row: row, photoFileId: photoIndex >= 0 ? row[photoIndex] : '' };
}

function appendRow_(sheet, header, record, aadhaar) {
  var now = new Date().toISOString();
  if (!record.createdAt) record.createdAt = now;
  record.updatedAt = now;
  var built = buildRow_(header, record, null, aadhaar);
  sheet.appendRow(built.row);
  return built.photoFileId;
}

function writeRow_(sheet, header, rowIndex, record, aadhaar) {
  var range = sheet.getRange(rowIndex, 1, 1, header.length);
  var existing = range.getValues()[0];
  record.updatedAt = new Date().toISOString();
  var built = buildRow_(header, record, existing, aadhaar);
  range.setValues([built.row]);
  return built.photoFileId;
}

function uploadPhoto_(aadhaar, base64) {
  try {
    var cleaned = String(base64).replace(/^data:[^;]+;base64,/, '');
    var blob = Utilities.newBlob(
      Utilities.base64Decode(cleaned),
      'image/jpeg',
      (aadhaar || 'record') + '_' + Date.now() + '.jpg'
    );
    var file = getPhotoFolder_().createFile(blob);
    // The app loads photos via the public thumbnail URL, so the file must be
    // readable by anyone with the link.
    try {
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch (shareError) {
      // Domain may forbid link sharing; the app falls back to initials.
    }
    return file.getId();
  } catch (error) {
    return '';
  }
}

function trashPhoto_(fileId) {
  if (!fileId) return;
  try {
    DriveApp.getFileById(String(fileId)).setTrashed(true);
  } catch (error) {
    // Best-effort; a leftover file is harmless.
  }
}

function getPhotoFolder_() {
  var folders = DriveApp.getFoldersByName(PHOTO_FOLDER_NAME);
  if (folders.hasNext()) {
    return folders.next();
  }
  return DriveApp.createFolder(PHOTO_FOLDER_NAME);
}
