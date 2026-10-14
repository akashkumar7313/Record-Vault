(() => {
  "use strict";

  const DEFAULT_ENDPOINT =
    "https://script.google.com/macros/s/AKfycbwln52lRzFfn-G-jTntwRBWm3ijeOZXjNEJZAKX7DHMm7iKvWO8dfL-lw5rVWscnQ4NJQ/exec";
  const TIMEOUT_MS = 20000;
  const READ_RETRIES = 3;
  const WRITE_RETRIES = 2;
  const BACKOFF_MS = 600;
  const RECENT_LIMIT = 5;
  const APP_VERSION = "1.0.0";

  const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const GENDERS = [
    { value: "male", label: "Male" },
    { value: "female", label: "Female" },
  ];
  const SYNC = {
    synced: { label: "Synced", color: "var(--synced)", icon: "cloud_done" },
    pending: { label: "Pending", color: "var(--pending)", icon: "cloud_upload" },
    failed: { label: "Failed", color: "var(--error)", icon: "cloud_off" },
    conflict: { label: "Conflict", color: "var(--conflict)", icon: "sync_problem" },
  };

  const S = {
    tab: "dashboard",
    records: [],
    loading: true,
    error: null,
    query: "",
    lastSyncAt: null,
    themeMode: "system",
    online: navigator.onLine,
  };

  const el = (id) => document.getElementById(id);
  const esc = (v) =>
    String(v == null ? "" : v).replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const pad = (n) => String(n).padStart(2, "0");

  function endpoint() {
    const fromStorage = localStorage.getItem("rv_endpoint");
    if (fromStorage && fromStorage.includes("AKfycbxxI3djYjtuiklxeY4k0-V2xl3O17GabLh998zUdMa70uBLrRfsGiXgmEBNa9mXa9_9")) {
      localStorage.removeItem("rv_endpoint");
    }
    const cleanStorage = localStorage.getItem("rv_endpoint");
    const fromQuery = new URLSearchParams(location.search).get("endpoint");
    const override = fromQuery || cleanStorage;
    return (override && override.trim()) || DEFAULT_ENDPOINT;
  }

  function hasCustomEndpoint() {
    return endpoint() !== DEFAULT_ENDPOINT;
  }

  function parseDateAny(value) {
    if (value == null || value === "") return null;
    if (typeof value === "number") return new Date(value);
    const text = String(value).trim();
    if (!text) return null;
    const iso = new Date(text);
    if (!isNaN(iso.getTime())) return iso;
    const asInt = Number(text);
    if (!isNaN(asInt) && text.match(/^\d+$/)) return new Date(asInt);
    const parts = text.split(/[/-]/);
    if (parts.length === 3) {
      const [p0, p1, p2] = parts.map(Number);
      if (p0 != null && p1 != null && p2 != null) {
        const d = p0 > 31 ? new Date(p0, p1 - 1, p2) : new Date(p2, p1 - 1, p0);
        if (!isNaN(d.getTime())) return d;
      }
    }
    return null;
  }

  function fmtDate(value) {
    const d = value instanceof Date ? value : parseDateAny(value);
    if (!d) return "";
    return `${pad(d.getDate())} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  }

  function fmtDateTime(value) {
    const d = value instanceof Date ? value : parseDateAny(value);
    if (!d) return "";
    let h = d.getHours();
    const ampm = h >= 12 ? "PM" : "AM";
    h = h % 12 || 12;
    return `${pad(d.getDate())} ${MONTHS[d.getMonth()]} ${d.getFullYear()}, ${pad(h)}:${pad(d.getMinutes())} ${ampm}`;
  }

  function isoDate(d) {
    if (!d) return "";
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  function ageLabel(dob) {
    const d = parseDateAny(dob);
    if (!d) return "";
    const now = new Date();
    let years = now.getFullYear() - d.getFullYear();
    const had = now.getMonth() > d.getMonth() || (now.getMonth() === d.getMonth() && now.getDate() >= d.getDate());
    if (!had) years--;
    return `${years} ${years === 1 ? "year" : "years"}`;
  }

  function fileStamp(d) {
    const x = d || new Date();
    return `${x.getFullYear()}${pad(x.getMonth() + 1)}${pad(x.getDate())}_${pad(x.getHours())}${pad(x.getMinutes())}${pad(x.getSeconds())}`;
  }

  function initials(name) {
    const parts = String(name || "").trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return "?";
    if (parts.length === 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  function maskAadhaar(value) {
    const digits = String(value || "").replace(/[^0-9]/g, "");
    if (!digits) return "No Aadhaar";
    if (digits.length <= 4) return "\u2022\u2022\u2022\u2022";
    return "\u2022\u2022\u2022\u2022 " + digits.slice(-4);
  }

  function normAadhaar(v) {
    return String(v || "").replace(/[\s-]/g, "");
  }

  function normMobile(v) {
    let digits = String(v || "").replace(/[^0-9]/g, "");
    if (digits.length > 10 && digits.startsWith("91")) digits = digits.slice(2);
    if (digits.length > 10 && digits.startsWith("0")) digits = digits.slice(-10);
    return digits;
  }

  const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;

  const Validators = {
    applicationNo(v) {
      const t = String(v || "").trim();
      if (t.length > 40) return "Application number is too long";
      return null;
    },
    name(v) {
      const t = String(v || "").trim();
      if (!t) return "Name is required";
      if (t.length < 2) return "Enter a valid name";
      return null;
    },
    guardianName(v) {
      const t = String(v || "").trim();
      if (!t) return "This name is required";
      if (t.length < 2) return "Enter a valid name";
      return null;
    },
    relation(v) {
      const t = String(v || "").trim();
      if (!t) return "Relation is required";
      return null;
    },
    gender(v) {
      if (!v) return "Please select Male or Female";
      if (!GENDERS.some((g) => g.value === v)) return "Select a valid option";
      return null;
    },
    aadhaar(v) {
      const t = String(v || "").trim();
      if (!t) return "Aadhaar number is required";
      if (!/^[0-9]{12}$/.test(normAadhaar(t))) return "Enter a valid 12-digit Aadhaar number";
      return null;
    },
    address(v) {
      const t = String(v || "").trim();
      if (!t) return "Address is required";
      if (t.length < 3) return "Enter a complete address";
      return null;
    },
    bankName(v) {
      const t = String(v || "").trim();
      if (!t) return "Bank name is required";
      if (t.length < 2) return "Enter a valid bank name";
      return null;
    },
    accountNumber(v) {
      const t = String(v || "").trim();
      if (!t) return "Account number is required";
      if (!/^[0-9]{9,18}$/.test(t)) return "Enter a valid account number (9\u201318 digits)";
      return null;
    },
    ifsc(v) {
      const t = String(v || "").trim().toUpperCase();
      if (!t) return "IFSC code is required";
      if (!IFSC_RE.test(t)) return "Enter a valid IFSC code (e.g. SBIN0001234)";
      return null;
    },
    addressCorrect(v) {
      const t = String(v || "").trim();
      if (t && t.length < 3) return "Enter a complete address";
      return null;
    },
    mobileNumberCorrect(v) {
      const t = String(v || "").trim();
      if (!t) return null;
      if (!/^[6-9][0-9]{9}$/.test(normMobile(t))) return "Enter a valid 10-digit mobile number";
      return null;
    },
  };

  const FIELDS = [
    { key: "applicationNo", header: "Application No", label: "Application No", icon: "confirmation_number", type: "text", placeholder: "Optional", validator: Validators.applicationNo },
    { key: "name", header: "Name", label: "Name", icon: "person", type: "text", placeholder: "Full name", validator: Validators.name },
    { key: "guardianName", header: "Name / Father's or Husband's", label: "Name / Father's or Husband's", icon: "man", type: "text", placeholder: "Father's or husband's name", validator: Validators.guardianName },
    { key: "relation", header: "Relation", label: "Relation", icon: "diversity_3", type: "text", placeholder: "Father / Husband", validator: Validators.relation },
    { key: "gender", header: "Male / Female", label: "Male / Female", icon: "wc", type: "select", validator: Validators.gender },
    { key: "aadhaarNumber", header: "Aadhaar Number", label: "Aadhaar Number", icon: "badge", type: "text", numeric: 12, placeholder: "12-digit number", validator: Validators.aadhaar },
    { key: "address", header: "Address", label: "Address", icon: "location_on", type: "textarea", placeholder: "Full address", validator: Validators.address },
    { key: "bankName", header: "Bank Name", label: "Bank Name", icon: "account_balance", type: "text", placeholder: "Bank name", validator: Validators.bankName },
    { key: "accountNumber", header: "Account Number", label: "Account Number", icon: "numbers", type: "text", numeric: 18, placeholder: "Bank account number", validator: Validators.accountNumber },
    { key: "ifscCode", header: "IFSC Code", label: "IFSC Code", icon: "pin", type: "text", uppercase: true, placeholder: "e.g. SBIN0001234", validator: Validators.ifsc },
    { key: "addressCorrect", header: "Address Correct", label: "Address Correct", icon: "home_pin", type: "textarea", placeholder: "Corrected address (if any)", validator: Validators.addressCorrect },
    { key: "mobileNumberCorrect", header: "Mobile Number Correct", label: "Mobile Number Correct", icon: "call", type: "text", numeric: 10, placeholder: "10-digit mobile number", validator: Validators.mobileNumberCorrect },
    { key: "remarks", header: "Remarks", label: "Remarks", icon: "sticky_note_2", type: "textarea", placeholder: "Any remarks", validator: null },
  ];

  function genderLabel(value) {
    const found = GENDERS.find((g) => g.value === String(value || "").toLowerCase());
    if (found) return found.label;
    return value ? String(value).charAt(0).toUpperCase() + String(value).slice(1) : "";
  }

  function greeting() {
    const h = new Date().getHours();
    if (h < 12) return "Good morning";
    if (h < 17) return "Good afternoon";
    return "Good evening";
  }

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  const Api = {
    headers(method) {
      if (method === "GET") return { Accept: "application/json" };
      return { "Content-Type": "text/plain;charset=utf-8", Accept: "application/json" };
    },

    async send(method, body, attempts) {
      let lastErr;
      for (let attempt = 1; attempt <= attempts; attempt++) {
        try {
          return await this.sendOnce(method, body);
        } catch (e) {
          lastErr = e;
          if (!e.retryable || attempt === attempts) throw e;
          await sleep(BACKOFF_MS * attempt);
        }
      }
      throw lastErr;
    },

    async sendOnce(method, body) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
      let res;
      try {
        res = await fetch(endpoint(), {
          method,
          headers: this.headers(method),
          body: method === "GET" ? undefined : (body || ""),
          redirect: "follow",
          signal: controller.signal,
        });
      } catch (e) {
        clearTimeout(timer);
        const err = new Error(
          e.name === "AbortError" ? "The server took too long to respond." : "Could not reach the server."
        );
        err.retryable = true;
        throw err;
      }
      clearTimeout(timer);

      if (res.status >= 500) {
        const err = new Error(`The server is temporarily unavailable (${res.status}).`);
        err.retryable = true;
        throw err;
      }
      if (res.status >= 400) {
        throw new Error(`The server rejected the request (${res.status}).`);
      }

      const raw = (await res.text()).trim();
      if (!raw) throw new Error("The server returned an empty response.");
      if (raw.startsWith("<")) {
        throw new Error(
          "The server did not return data. The web app may not be shared for public access, or access is restricted."
        );
      }
      try {
        return JSON.parse(raw);
      } catch (e) {
        throw new Error("Received an unexpected response format from the server.");
      }
    },

    async fetchRecords() {
      let decoded;
      try {
        decoded = await this.send("GET", null, READ_RETRIES);
      } catch (getErr) {
        try {
          decoded = await this.send("POST", JSON.stringify({ action: "read" }), WRITE_RETRIES);
        } catch (postErr) {
          throw getErr;
        }
      }
      const list = extractRecordList(decoded);
      return list.filter((r) => r && typeof r === "object").map(normalizeRecord).filter((r) => r.aadhaarNumber);
    },

    async addRecord(record) {
      return this.mutate("add", record);
    },

    async updateRecord(record) {
      return this.mutate("update", record);
    },

    async deleteRecord(aadhaar) {
      const decoded = await this.send(
        "POST",
        JSON.stringify({ action: "delete", record: { "Aadhaar Number": aadhaar, aadhaarNumber: aadhaar } }),
        WRITE_RETRIES
      );
      return interpretWrite(decoded, aadhaar);
    },

    async mutate(action, record) {
      const decoded = await this.send(
        "POST",
        JSON.stringify({ action, record: toRemoteJson(record) }),
        WRITE_RETRIES
      );
      return interpretWrite(decoded, record.aadhaarNumber);
    },

    async checkConnection() {
      try {
        await this.send("GET", null, 1);
        return true;
      } catch (e) {
        return false;
      }
    },
  };

  function pick(json, keys) {
    for (const key of keys) {
      if (json[key] != null && json[key] !== "") return json[key];
    }
    return null;
  }

  function normalizeRecord(item) {
    const created = parseDateAny(pick(item, ["Created At", "createdAt", "created_at", "created"]));
    const updated = parseDateAny(pick(item, ["Updated At", "updatedAt", "updated_at", "updated"])) || created;
    return {
      applicationNo: String(pick(item, ["Application No", "applicationNo", "application_no", "appNo"]) || ""),
      name: String(pick(item, ["Name", "name", "fullName", "full_name"]) || ""),
      guardianName: String(
        pick(item, ["Name / Father's or Husband's", "guardianName", "fatherName", "father_name", "husbandName"]) || ""
      ),
      relation: String(pick(item, ["Relation", "relation", "relationship"]) || ""),
      gender: String(pick(item, ["Male / Female", "gender", "Gender"]) || "").toLowerCase(),
      aadhaarNumber: String(
        pick(item, ["Aadhaar Number", "aadhaarNumber", "aadhaar_number", "aadhaar", "aadhar", "id", "recordId"]) || ""
      ),
      address: String(pick(item, ["Address", "address"]) || ""),
      bankName: String(pick(item, ["Bank Name", "bankName", "bank_name"]) || ""),
      accountNumber: String(pick(item, ["Account Number", "accountNumber", "account_number"]) || ""),
      ifscCode: String(pick(item, ["IFSC Code", "ifscCode", "ifsc_code", "ifsc"]) || ""),
      addressCorrect: String(pick(item, ["Address Correct", "addressCorrect", "address_correct"]) || ""),
      mobileNumberCorrect: String(
        pick(item, ["Mobile Number Correct", "mobileNumberCorrect", "mobileNumber", "mobile_number", "mobile"]) || ""
      ),
      remarks: String(pick(item, ["Remarks", "remarks", "remark"]) || ""),
      createdAt: created,
      updatedAt: updated || created || new Date(),
      syncStatus: "synced",
    };
  }

  function toRemoteJson(record) {
    return {
      "Application No": record.applicationNo || "",
      "Name": record.name || "",
      "Name / Father's or Husband's": record.guardianName || "",
      "Relation": record.relation || "",
      "Male / Female": record.gender || "",
      "Aadhaar Number": record.aadhaarNumber || "",
      "Address": record.address || "",
      "Bank Name": record.bankName || "",
      "Account Number": record.accountNumber || "",
      "IFSC Code": record.ifscCode || "",
      "Address Correct": record.addressCorrect || "",
      "Mobile Number Correct": record.mobileNumberCorrect || "",
      "Remarks": record.remarks || "",
      "Created At": record.createdAt instanceof Date ? record.createdAt.toISOString() : (record.createdAt || new Date().toISOString()),
      "Updated At": record.updatedAt instanceof Date ? record.updatedAt.toISOString() : (record.updatedAt || new Date().toISOString()),
    };
  }

  function extractRecordList(decoded) {
    if (Array.isArray(decoded)) return decoded;
    if (decoded && typeof decoded === "object") {
      if (typeof decoded.error === "string" && decoded.error.trim()) {
        throw new Error(`Server error: ${decoded.error}`);
      }
      for (const key of ["records", "data", "rows", "items", "values"]) {
        if (Array.isArray(decoded[key])) return decoded[key];
      }
      if ("aadhaarNumber" in decoded || "id" in decoded || "Aadhaar Number" in decoded) return [decoded];
    }
    throw new Error("The server response did not contain a records list.");
  }

  function interpretWrite(decoded, expectedAadhaar) {
    if (Array.isArray(decoded)) {
      return decoded.length
        ? { confirmed: true, message: "Confirmed by server" }
        : { confirmed: false, message: "Server returned no confirmation for this change." };
    }
    if (decoded && typeof decoded === "object") {
      const photoFileId =
        decoded.photoFileId != null && String(decoded.photoFileId).trim() ? String(decoded.photoFileId).trim() : null;
      const error = decoded.error;
      if (error != null) {
        const n = String(error).trim().toLowerCase();
        if (n && n !== "false" && n !== "null" && n !== "none") {
          const unsupported = n.includes("unknown action") || n.includes("unsupported") || n.includes("not implemented");
          return unsupported
            ? { confirmed: false, unsupported: true, message: "The server does not support this action yet." }
            : { confirmed: false, message: `Server reported an error: ${error}` };
        }
      }
      const statusValue = decoded.status != null ? String(decoded.status).trim().toLowerCase() : "";
      const statusOk = ["success", "ok", "added", "updated", "deleted", "upserted"].includes(statusValue);
      const messageValue = decoded.message != null ? String(decoded.message).trim().toLowerCase() : "";
      const unsupportedMessage =
        messageValue && (messageValue.includes("unsupported") || messageValue.includes("unknown action") || messageValue.includes("not implemented"));

      if (typeof decoded.success === "boolean") {
        if (decoded.success) return { confirmed: true, message: "Confirmed by server", photoFileId };
        if (unsupportedMessage)
          return { confirmed: false, unsupported: true, message: "The server does not support this action yet." };
        return {
          confirmed: false,
          message: messageValue ? `Server did not confirm the change: ${decoded.message}` : "Server did not confirm the change.",
        };
      }
      if (statusOk) return { confirmed: true, message: "Confirmed by server", photoFileId };

      for (const key of ["result", "state", "message"]) {
        const value = decoded[key] != null ? String(decoded[key]).trim().toLowerCase() : "";
        if (!value) continue;
        if (["success", "ok", "added", "updated", "deleted", "upserted"].some((v) => value === v || value.includes("success")))
          return { confirmed: true, message: "Confirmed by server", photoFileId };
        if (value.includes("unknown action") || value.includes("unsupported") || value.includes("not implemented"))
          return { confirmed: false, unsupported: true, message: "The server does not support this action yet." };
        if (value.includes("error") || value.includes("fail"))
          return { confirmed: false, message: "Server did not confirm the change." };
      }

      const echoed =
        decoded.aadhaarNumber ||
        decoded.id ||
        (decoded.record && (decoded.record.aadhaarNumber || decoded.record.id));
      if (echoed != null && String(echoed) === expectedAadhaar)
        return { confirmed: true, message: "Confirmed by server", photoFileId };
    }
    return { confirmed: false, message: "Server did not confirm the change." };
  }

  function avatarHtml(record, radius) {
    const size = radius * 2;
    return `<span class="avatar" style="width:${size}px;height:${size}px;font-size:${Math.round(radius * 0.72)}px"><span class="ini">${esc(initials(record.name))}</span></span>`;
  }

  function statusChip(status, dense) {
    const s = SYNC[status] || SYNC.synced;
    return `<span class="status-chip" style="background:color-mix(in srgb, ${s.color} 15%, transparent);color:${s.color}">
      <span class="material-symbols-outlined">${s.icon}</span>${s.label}</span>`;
  }

  function stats() {
    const total = S.records.length;
    return { total, synced: total, pending: 0, conflicts: 0 };
  }

  function filteredRecords() {
    const q = S.query.trim().toLowerCase();
    if (!q) return S.records;
    return S.records.filter((r) =>
      [r.name, r.guardianName, r.relation, r.aadhaarNumber, r.accountNumber, r.applicationNo, r.bankName, r.mobileNumberCorrect, r.ifscCode]
        .some((v) => String(v || "").toLowerCase().includes(q))
    );
  }

  function snackbar(message, ms) {
    const host = el("snackbarHost");
    const node = document.createElement("div");
    node.className = "snackbar";
    node.textContent = message;
    host.appendChild(node);
    setTimeout(() => {
      node.style.transition = "opacity .2s";
      node.style.opacity = "0";
      setTimeout(() => node.remove(), 200);
    }, ms || 3000);
  }

  const media = window.matchMedia("(prefers-color-scheme: dark)");
  function applyTheme() {
    const resolved = S.themeMode === "system" ? (media.matches ? "dark" : "light") : S.themeMode;
    document.documentElement.setAttribute("data-theme", resolved);
  }
  media.addEventListener("change", () => {
    if (S.themeMode === "system") applyTheme();
  });

  function setThemeMode(mode) {
    S.themeMode = mode;
    localStorage.setItem("rv_theme", mode);
    applyTheme();
    if (S.tab === "settings") render();
  }

  /* ---- Sheets / modal ---- */
  function openSheet(innerHtml, kind) {
    const host = el("sheetHost");
    host.innerHTML = `<div class="scrim" data-close></div>${kind === "dialog" ? `<div class="dialog">${innerHtml}</div>` : `<div class="sheet"><div class="sheet-header"></div><div class="sheet-body"></div></div>`}`;
    if (kind !== "dialog") {
      const sheet = host.querySelector(".sheet");
      sheet.querySelector(".sheet-header").innerHTML = innerHtml.header || "";
      sheet.querySelector(".sheet-body").innerHTML = innerHtml.body || "";
    }
    host.classList.add("open");
    host.querySelectorAll("[data-close]").forEach((n) => n.addEventListener("click", closeSheet));
  }

  function closeSheet() {
    const host = el("sheetHost");
    host.classList.remove("open");
    host.innerHTML = "";
  }

  function confirmDialog({ title, message, confirmLabel, destructive }) {
    return new Promise((resolve) => {
      openSheet(
        `<h2>${esc(title)}</h2><div class="body">${esc(message)}</div>
         <div class="actions">
           <button class="btn" data-act="cancel" type="button">Cancel</button>
           <button class="btn ${destructive ? "btn-danger" : "btn-filled"}" data-act="ok" type="button">${esc(confirmLabel)}</button>
         </div>`,
        "dialog"
      );
      const host = el("sheetHost");
      host.querySelector('[data-act="cancel"]').addEventListener("click", () => {
        closeSheet();
        resolve(false);
      });
      host.querySelector('[data-act="ok"]').addEventListener("click", () => {
        closeSheet();
        resolve(true);
      });
    });
  }

  /* ---- Appbar + nav ---- */
  function renderAppbar() {
    const bar = el("appbar");
    if (S.tab === "dashboard") {
      bar.innerHTML = `
        <div class="title">
          <h1>${esc(greeting())}</h1>
          <span class="sub">${esc(fmtDate(new Date()))}</span>
        </div>
        <button class="icon-btn" id="syncBtn" title="Sync now" type="button">
          <span class="material-symbols-outlined">sync</span>
        </button>`;
      el("syncBtn").addEventListener("click", () => syncNow(false));
    } else if (S.tab === "records") {
      const st = stats();
      bar.innerHTML = `
        <div class="title"><h1>Records</h1></div>
        ${st.pending > 0 ? statusChip("pending", true) : ""}`;
    } else {
      bar.innerHTML = `<div class="title"><h1>Settings</h1></div>`;
    }
  }

  function renderNav() {
    document.querySelectorAll(".nav-item").forEach((n) => {
      n.classList.toggle("is-active", n.dataset.tab === S.tab);
    });
    const fab = el("fab");
    fab.hidden = !(S.tab === "dashboard" || S.tab === "records");
  }

  function setTab(tab) {
    if (S.tab === tab) return;
    S.tab = tab;
    try { history.replaceState(null, "", "#" + tab); } catch (e) { }
    render();
    window.scrollTo({ top: 0 });
  }

  /* ---- Views ---- */
  function render() {
    renderAppbar();
    renderNav();
    const content = el("content");
    if (S.loading) {
      content.innerHTML = `<div class="loader"><span class="spinner"></span></div>`;
      return;
    }
    if (S.error) {
      content.innerHTML = `
        <div class="error-view">
          <span class="material-symbols-outlined">error</span>
          <div>${esc(S.error)}</div>
          <button class="btn btn-tonal" id="retryBtn" type="button">
            <span class="material-symbols-outlined">refresh</span>Retry
          </button>
        </div>`;
      el("retryBtn").addEventListener("click", () => loadRecords());
      return;
    }
    if (S.tab === "dashboard") renderDashboard(content);
    else if (S.tab === "records") renderRecords(content);
    else renderSettings(content);
  }

  function renderDashboard(c) {
    const st = stats();
    const recent = [...S.records].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, RECENT_LIMIT);
    const value = st.total === 0 ? 0 : st.synced / st.total;
    const accent = st.conflicts > 0 ? "var(--error)" : st.pending > 0 ? "var(--pending)" : "var(--synced)";
    const headline =
      st.total === 0
        ? "Welcome to your vault"
        : st.conflicts > 0
          ? "Conflicts need attention"
          : st.pending > 0
            ? `${st.pending} change${st.pending === 1 ? "" : "s"} waiting to sync`
            : "Everything is up to date";
    const subline = S.lastSyncAt
      ? `Last synced ${fmtDateTime(S.lastSyncAt)}`
      : st.total === 0
        ? "Records are stored in Google Sheets."
        : "Records are stored in Google Sheets.";

    const circumference = 2 * Math.PI * 30;
    const dash = circumference * value;

    const recentHtml = recent.length
      ? recent
        .map(
          (r) => `
        <div class="recent" data-open="${esc(r.aadhaarNumber)}">
          ${avatarHtml(r, 22)}
          <div class="info">
            <div class="name">${esc(r.name || "Unnamed record")}</div>
            <div class="contact">${esc(r.mobileNumberCorrect || r.relation || r.applicationNo || "No contact details")}</div>
            <div class="aadhaar mono">${esc(maskAadhaar(r.aadhaarNumber))}</div>
          </div>
          <span class="status-dot">${statusChip(r.syncStatus, true)}</span>
          <span class="material-symbols-outlined" style="color:var(--on-surface-variant)">chevron_right</span>
        </div>`
        )
        .join("")
      : `<div class="empty">
          <span class="material-symbols-outlined">person_add_alt</span>
          <h3>Welcome to RecordVault</h3>
          <p>Store personal records in Google Sheets and access them from anywhere.</p>
        </div>`;

    c.innerHTML = `
      ${S.online === false ? `<div class="card" style="padding:12px 16px;margin-bottom:12px;background:var(--secondary-container);color:var(--on-secondary-container);border:none">Offline \u2014 changes will be saved when you reconnect.</div>` : ""}
      <div class="card" style="padding:16px">
        <div class="summary-head">
          <div class="ring">
            <svg width="68" height="68" viewBox="0 0 68 68">
              <circle cx="34" cy="34" r="30" fill="none" stroke="color-mix(in srgb, ${accent} 18%, transparent)" stroke-width="6"></circle>
              <circle cx="34" cy="34" r="30" fill="none" stroke="${accent}" stroke-width="6" stroke-linecap="round"
                stroke-dasharray="${dash} ${circumference}" ></circle>
            </svg>
            <div class="ring-text">${st.total === 0 ? "\u2014" : `${st.synced}/${st.total}`}</div>
          </div>
          <div style="flex:1;min-width:0">
            <div class="headline">${esc(headline)}</div>
            <div class="subline">${esc(subline)}</div>
          </div>
        </div>
        <div class="chips">
          <span class="chip" style="background:color-mix(in srgb,var(--on-surface-variant) 10%,transparent);color:var(--on-surface-variant)"><span class="material-symbols-outlined">people</span>${st.total} total</span>
          <span class="chip" style="background:color-mix(in srgb,var(--synced) 12%,transparent);color:var(--synced)"><span class="material-symbols-outlined">cloud_done</span>${st.synced} synced</span>
          <span class="chip" style="background:color-mix(in srgb,var(--pending) 12%,transparent);color:var(--pending)"><span class="material-symbols-outlined">cloud_upload</span>${st.pending} pending</span>
        </div>
        <div class="spacer"></div>
        <button class="btn btn-tonal btn-block" id="summarySync" type="button">
          <span class="material-symbols-outlined">sync</span>Sync now
        </button>
      </div>

      <div class="section-title"><div><h2>Find a record</h2><p>Search by name, Aadhaar, account or mobile</p></div></div>
      <div class="search">
        <span class="material-symbols-outlined">search</span>
        <input id="dashSearch" type="search" placeholder="Search records" value="${esc(S.query)}" autocomplete="off">
      </div>
      ${S.query.trim() ? `<div style="margin-top:8px"><button class="text-link" id="openResults" type="button"><span class="material-symbols-outlined" style="font-size:16px;vertical-align:-3px">arrow_forward</span> Open search results in Records</button></div>` : ""}

      <div class="section-title"><h2>Recent records</h2><button class="text-link" id="seeAll" type="button">See all</button></div>
      <div class="card" style="padding:4px">${recentHtml}</div>

      <div class="section-title"><h2>Quick actions</h2></div>
      <div class="card quick">
        <button data-quick="add" type="button"><span class="badge"><span class="material-symbols-outlined">person_add</span></span><span class="label">Add record</span></button>
        <button data-quick="browse" type="button"><span class="badge"><span class="material-symbols-outlined">folder_copy</span></span><span class="label">Browse</span></button>
        <button data-quick="settings" type="button"><span class="badge"><span class="material-symbols-outlined">tune</span></span><span class="label">Settings</span></button>
      </div>`;

    el("summarySync").addEventListener("click", () => syncNow(false));
    const dashSearch = el("dashSearch");
    dashSearch.addEventListener("input", () => {
      S.query = dashSearch.value;
    });
    dashSearch.addEventListener("keydown", (e) => {
      if (e.key === "Enter") setTab("records");
    });
    const openResults = el("openResults");
    if (openResults) openResults.addEventListener("click", () => setTab("records"));
    el("seeAll").addEventListener("click", () => setTab("records"));
    c.querySelectorAll("[data-open]").forEach((n) => n.addEventListener("click", () => openDetails(n.dataset.open)));
    c.querySelectorAll("[data-quick]").forEach((n) =>
      n.addEventListener("click", () => {
        const q = n.dataset.quick;
        if (q === "add") openForm(null);
        if (q === "browse") setTab("records");
        if (q === "settings") setTab("settings");
      })
    );
  }

  function renderRecords(c) {
    const list = filteredRecords().sort((a, b) => b.updatedAt - a.updatedAt);
    let listHtml;
    if (!S.records.length) {
      listHtml = `<div class="empty">
        <span class="material-symbols-outlined">person_search</span>
        <h3>No records yet</h3>
        <p>Tap the + button to add your first record.</p>
        <button class="btn btn-filled" id="emptyAdd" type="button">Add record</button>
      </div>`;
    } else if (!list.length) {
      listHtml = `<div class="empty">
        <span class="material-symbols-outlined">person_search</span>
        <h3>No matching records</h3>
        <p>Try a different name, Aadhaar, account or mobile number.</p>
      </div>`;
    } else {
      listHtml = list
        .map(
          (r) => `
        <div class="card record-card">
          ${avatarHtml(r, 26)}
          <div class="info" data-open="${esc(r.aadhaarNumber)}">
            <div class="name">${esc(r.name || "Unnamed record")}</div>
            <div class="contact">${esc(r.mobileNumberCorrect || r.relation || r.applicationNo || "No contact details")}</div>
            <div class="meta">
              ${statusChip(r.syncStatus, true)}
              <span class="updated">Updated ${esc(fmtDateTime(r.updatedAt))}</span>
            </div>
          </div>
          <button class="icon-btn" data-menu="${esc(r.aadhaarNumber)}" type="button"><span class="material-symbols-outlined">more_vert</span></button>
        </div>`
        )
        .join("");
    }

    c.innerHTML = `
      <div class="search" style="margin-bottom:12px">
        <span class="material-symbols-outlined">search</span>
        <input id="recSearch" type="search" placeholder="Search records" value="${esc(S.query)}" autocomplete="off">
      </div>
      <div id="recList">${listHtml}</div>`;

    const search = el("recSearch");
    search.addEventListener("input", () => {
      S.query = search.value;
      const pos = search.selectionStart;
      renderRecords(c);
      const next = el("recSearch");
      if (next) {
        next.focus();
        try { next.setSelectionRange(pos, pos); } catch (e) { }
      }
    });
    const emptyAdd = el("emptyAdd");
    if (emptyAdd) emptyAdd.addEventListener("click", () => openForm(null));
    c.querySelectorAll("[data-open]").forEach((n) => n.addEventListener("click", () => openDetails(n.dataset.open)));
    c.querySelectorAll("[data-menu]").forEach((n) => n.addEventListener("click", (e) => openRowMenu(e, n.dataset.menu)));
  }

  function openRowMenu(event, aadhaar) {
    event.stopPropagation();
    const target = event.currentTarget;
    const existing = target.parentNode.querySelector(".row-menu");
    if (existing) { existing.remove(); return; }
    const menu = document.createElement("div");
    menu.className = "row-menu";
    menu.style.cssText = "position:absolute;background:var(--surface);border:1px solid var(--outline-variant);border-radius:12px;box-shadow:var(--shadow);padding:4px;z-index:30";
    const r = target.getBoundingClientRect();
    menu.style.top = `${r.bottom + window.scrollY + 4}px`;
    menu.style.left = `${Math.max(8, r.right - 160 + window.scrollX)}px`;
    menu.innerHTML = `
      <button class="text-link" data-menu-act="edit" style="display:flex;gap:10px;align-items:center;color:var(--on-surface);width:100%;justify-content:flex-start"><span class="material-symbols-outlined" style="font-size:18px">edit</span>Edit</button>
      <button class="text-link" data-menu-act="delete" style="display:flex;gap:10px;align-items:center;color:var(--error);width:100%;justify-content:flex-start"><span class="material-symbols-outlined" style="font-size:18px">delete</span>Delete</button>`;
    document.body.appendChild(menu);
    const cleanup = (ev) => { if (!menu.contains(ev.target)) { menu.remove(); document.removeEventListener("click", cleanup); } };
    setTimeout(() => document.addEventListener("click", cleanup), 0);
    menu.querySelector('[data-menu-act="edit"]').addEventListener("click", () => {
      menu.remove();
      const record = S.records.find((x) => x.aadhaarNumber === aadhaar);
      if (record) openForm(record);
    });
    menu.querySelector('[data-menu-act="delete"]').addEventListener("click", () => {
      menu.remove();
      deleteRecordFlow(aadhaar);
    });
  }

  function renderSettings(c) {
    const st = stats();
    c.innerHTML = `
      <div class="card" style="padding:16px">
        <div class="summary-head">
          <div class="ring">
            <svg width="68" height="68" viewBox="0 0 68 68">
              <circle cx="34" cy="34" r="30" fill="none" stroke="color-mix(in srgb,var(--synced) 18%,transparent)" stroke-width="6"></circle>
              <circle cx="34" cy="34" r="30" fill="none" stroke="var(--synced)" stroke-width="6" stroke-linecap="round"
                stroke-dasharray="${2 * Math.PI * 30} ${2 * Math.PI * 30}"></circle>
            </svg>
            <div class="ring-text">${st.total === 0 ? "\u2014" : `${st.synced}/${st.total}`}</div>
          </div>
          <div style="flex:1;min-width:0">
            <div class="headline">${st.total === 0 ? "Welcome to your vault" : "Everything is up to date"}</div>
            <div class="subline">${S.lastSyncAt ? esc("Last synced " + fmtDateTime(S.lastSyncAt)) : "Records are stored in Google Sheets."}</div>
          </div>
        </div>
        <div class="spacer"></div>
        <button class="btn btn-tonal btn-block" id="settingsSync" type="button"><span class="material-symbols-outlined">sync</span>Sync now</button>
      </div>

      <div class="section-label">Google Sheets connection</div>
      <div class="card" style="padding:16px">
        <div style="display:flex;align-items:center;gap:8px">
          <span class="material-symbols-outlined" id="connIcon" style="color:var(--on-surface-variant)">sync</span>
          <span id="connText" style="flex:1;font-size:14px;font-weight:500">Checking connection\u2026</span>
          <button class="text-link" id="testBtn" type="button">Test</button>
        </div>
        <div class="muted small" style="margin-top:8px">Endpoint: ${esc(new URL(endpoint()).host)}</div>
        <div class="muted small" style="margin-top:2px">${hasCustomEndpoint() ? "A custom endpoint is configured." : "Using the default shared endpoint. Treat it as untrusted."}</div>
      </div>

      <div class="section-label">Export records</div>
      <div class="card" style="padding:16px">
        <div>${st.total} record${st.total === 1 ? "" : "s"} will be exported.</div>
        <div class="muted small" style="margin-top:8px">Creates an .xlsx workbook containing every supported field.</div>
        <div class="spacer"></div>
        <div class="btn-row">
          <button class="btn btn-filled" id="shareBtn" type="button"><span class="material-symbols-outlined">ios_share</span>Share</button>
          <button class="btn btn-outlined" id="saveBtn" type="button"><span class="material-symbols-outlined">save</span>Save file</button>
        </div>
      </div>

      <div class="section-label">Appearance</div>
      <div class="segmented" id="themeSeg">
        <button data-mode="system" class="${S.themeMode === "system" ? "active" : ""}" type="button"><span class="material-symbols-outlined">brightness_auto</span>System</button>
        <button data-mode="light" class="${S.themeMode === "light" ? "active" : ""}" type="button"><span class="material-symbols-outlined">light_mode</span>Light</button>
        <button data-mode="dark" class="${S.themeMode === "dark" ? "active" : ""}" type="button"><span class="material-symbols-outlined">dark_mode</span>Dark</button>
      </div>

      <div class="section-label">Privacy</div>
      <div class="card setting-row" id="privacyRow" style="cursor:pointer">
        <span class="material-symbols-outlined" style="color:var(--primary)">shield</span>
        <div class="body"><div class="label">Privacy &amp; security</div><div class="desc">How your data is stored, synced and protected.</div></div>
        <span class="material-symbols-outlined">chevron_right</span>
      </div>

      <div class="center muted small" style="text-align:center;margin-top:32px;color:var(--on-surface-variant)">RecordVault ${APP_VERSION}</div>`;

    el("settingsSync").addEventListener("click", () => syncNow(false));
    el("testBtn").addEventListener("click", testConnection);
    el("shareBtn").addEventListener("click", () => doExport(true));
    el("saveBtn").addEventListener("click", () => doExport(false));
    el("privacyRow").addEventListener("click", showPrivacy);
    el("themeSeg").querySelectorAll("button").forEach((b) => b.addEventListener("click", () => setThemeMode(b.dataset.mode)));
    testConnection();
  }

  async function testConnection() {
    const icon = el("connIcon");
    const text = el("connText");
    if (!icon || !text) return;
    icon.textContent = "sync";
    icon.style.color = "var(--primary)";
    text.textContent = "Checking connection\u2026";
    const ok = await Api.checkConnection();
    if (!el("connText")) return;
    icon.textContent = ok ? "check_circle" : "error";
    icon.style.color = ok ? "var(--synced)" : "var(--error)";
    text.textContent = ok ? "Endpoint is reachable" : "Endpoint did not return usable data";
  }

  function showPrivacy() {
    openSheet(
      `<h2>Privacy &amp; security</h2>
       <div class="body">\u2022 Records are stored in your connected Google Sheet. Nothing is kept in this browser beyond your session.\n\n\u2022 The default Google Sheets endpoint is a PUBLIC web app. Anyone with the URL can read or write what it exposes. Only use an authenticated, access-controlled backend.\n\n\u2022 Export files contain personal information. Share them only with trusted recipients.\n\n\u2022 RecordVault does not collect or request Aadhaar or other government identifiers beyond what you enter.</div>
       <div class="actions"><button class="btn btn-tonal" data-close type="button">Got it</button></div>`,
      "dialog"
    );
  }

  function showError(e) {
    snackbar((e && e.message) || "Something went wrong. Please try again.", 4500);
  }

  /* ---- Data ops ---- */
  async function loadRecords() {
    S.loading = true;
    S.error = null;
    render();
    try {
      S.records = await Api.fetchRecords();
      S.lastSyncAt = new Date();
    } catch (e) {
      S.error = e.message || "Could not reach the server.";
    } finally {
      S.loading = false;
      render();
    }
  }

  async function syncNow(auto) {
    const btns = [el("syncBtn"), el("summarySync"), el("settingsSync")].filter(Boolean);
    btns.forEach((b) => { b.disabled = true; b.classList.add("spin"); });
    try {
      const records = await Api.fetchRecords();
      S.records = records;
      S.lastSyncAt = new Date();
      S.error = null;
      render();
      if (!auto) snackbar(`Synced ${records.length} record${records.length === 1 ? "" : "s"}.`);
    } catch (e) {
      if (!auto) showError(e);
      else snackbar("Sync failed. Your data is unchanged.", 4000);
    } finally {
      btns.forEach((b) => { b.classList.remove("spin"); });
    }
  }

  async function deleteRecordFlow(aadhaar) {
    const record = S.records.find((r) => r.aadhaarNumber === aadhaar);
    if (!record) return;
    const ok = await confirmDialog({
      title: "Delete record?",
      message: `This will remove "${record.name}" from RecordVault and the Google Sheet. This cannot be undone.`,
      confirmLabel: "Delete",
      destructive: true,
    });
    if (!ok) return;
    try {
      const result = await Api.deleteRecord(aadhaar);
      if (!result.confirmed) throw new Error(result.message || "Server did not confirm the deletion.");
      snackbar("Record deleted.");
      await syncNow(true);
    } catch (e) {
      showError(e);
    }
  }

  /* ---- Form sheet ---- */
  function openForm(existing) {
    const isEdit = !!existing;
    const g = (v) => esc(v == null ? "" : v);

    const header = `
      <h2>${isEdit ? "Edit record" : "Add record"}</h2>
      <button class="icon-btn" data-close type="button"><span class="material-symbols-outlined">close</span></button>`;

    const currentGender = existing && GENDERS.some((x) => x.value === existing.gender) ? existing.gender : "";

    const REQUIRED_KEYS = ["name", "guardianName", "relation", "gender", "aadhaarNumber", "address", "bankName", "accountNumber", "ifscCode"];

    const fieldHtml = (f) => {
      const req = REQUIRED_KEYS.includes(f.key) ? " *" : "";
      const ro = isEdit && f.key === "aadhaarNumber" ? "readonly" : "";
      const val = g(existing ? existing[f.key] : "");
      let control;
      if (f.type === "select") {
        const opts =
          `<option value="" disabled ${currentGender === "" ? "selected" : ""}>Select</option>` +
          GENDERS.map(
            (x) => `<option value="${x.value}" ${currentGender === x.value ? "selected" : ""}>${x.label}</option>`
          ).join("");
        control = `<div class="control"><span class="material-symbols-outlined">${f.icon}</span><select id="f_${f.key}">${opts}</select></div>`;
      } else if (f.type === "textarea") {
        control = `<div class="control" style="align-items:flex-start"><span class="material-symbols-outlined" style="margin-top:14px">${f.icon}</span>
          <textarea id="f_${f.key}" placeholder="${esc(f.placeholder || "")}">${val}</textarea></div>`;
      } else {
        const attrs = [
          f.numeric ? `inputmode="numeric" maxlength="${f.numeric}"` : "",
          f.uppercase ? 'style="text-transform:uppercase"' : "",
          ro,
        ]
          .filter(Boolean)
          .join(" ");
        control = `<div class="control"><span class="material-symbols-outlined">${f.icon}</span>
          <input id="f_${f.key}" placeholder="${esc(f.placeholder || "")}" value="${val}" ${attrs}></div>`;
      }
      return `
      <div class="field" data-field="${f.key}">
        <label>${esc(f.label)}${req}</label>
        ${control}
        <div class="error"></div>
      </div>`;
    };

    const body = `${FIELDS.map(fieldHtml).join("")}
      <div class="spacer"></div>
      <button class="btn btn-filled btn-block" id="saveBtn" type="button">
        <span class="material-symbols-outlined">save</span>${isEdit ? "Save changes" : "Save record"}
      </button>
      <p class="muted small" style="text-align:center;margin-top:12px">Records are saved to your connected Google Sheet.</p>`;

    openSheet({ header, body });

    const host = el("sheetHost");

    const setFieldError = (name, msg) => {
      const field = host.querySelector(`[data-field="${name}"]`);
      if (!field) return;
      field.classList.toggle("invalid", !!msg);
      const err = field.querySelector(".error");
      if (err) err.textContent = msg || "";
    };

    const validate = () => {
      const checks = FIELDS.map((f) => [f.key, f.validator ? f.validator(el("f_" + f.key).value) : null]);
      checks.forEach(([n, m]) => setFieldError(n, m));
      return !checks.some(([, m]) => m);
    };

    FIELDS.forEach((f) => {
      const input = el("f_" + f.key);
      if (!input) return;
      const live = () => setFieldError(f.key, f.validator ? f.validator(input.value) : null);
      if (f.numeric) {
        input.addEventListener("input", () => {
          const cleaned = input.value.replace(/[^0-9]/g, "").slice(0, f.numeric);
          if (cleaned !== input.value) {
            input.value = cleaned;
            try { input.setSelectionRange(cleaned.length, cleaned.length); } catch (e) { }
          }
          live();
        });
      } else if (f.uppercase) {
        input.addEventListener("input", () => {
          if (input.value !== input.value.toUpperCase()) input.value = input.value.toUpperCase();
          live();
        });
      } else {
        input.addEventListener("input", live);
      }
      if (f.type === "select") input.addEventListener("change", live);
      input.addEventListener("blur", live);
    });

    el("saveBtn").addEventListener("click", async () => {
      if (!validate()) {
        snackbar("Please fix the highlighted fields.", 3500);
        return;
      }
      const aadhaarNumber = normAadhaar(el("f_aadhaarNumber").value.trim());
      if (!isEdit && S.records.some((r) => r.aadhaarNumber === aadhaarNumber)) {
        snackbar(`A record with Aadhaar ${aadhaarNumber} already exists.`, 4000);
        return;
      }
      const now = new Date();
      const record = {
        applicationNo: el("f_applicationNo").value.trim(),
        name: el("f_name").value.trim(),
        guardianName: el("f_guardianName").value.trim(),
        relation: el("f_relation").value.trim(),
        gender: el("f_gender").value,
        aadhaarNumber,
        address: el("f_address").value.trim(),
        bankName: el("f_bankName").value.trim(),
        accountNumber: el("f_accountNumber").value.trim(),
        ifscCode: el("f_ifscCode").value.trim().toUpperCase(),
        addressCorrect: el("f_addressCorrect").value.trim(),
        mobileNumberCorrect: normMobile(el("f_mobileNumberCorrect").value.trim()),
        remarks: el("f_remarks").value.trim(),
        createdAt: (existing && existing.createdAt) || now,
        updatedAt: now,
      };

      const btn = el("saveBtn");
      btn.disabled = true;
      btn.innerHTML = `<span class="spinner" style="width:18px;height:18px;border-width:2px"></span>Saving\u2026`;
      try {
        const result = isEdit ? await Api.updateRecord(record) : await Api.addRecord(record);
        if (!result.confirmed) throw new Error(result.message || "Server did not confirm the save.");
        closeSheet();
        snackbar(isEdit ? "Record updated." : "Record saved.");
        await syncNow(true);
      } catch (e) {
        showError(e);
        btn.disabled = false;
        btn.innerHTML = `<span class="material-symbols-outlined">save</span>${isEdit ? "Save changes" : "Save record"}`;
      }
    });
  }

  /* ---- Details sheet ---- */
  function openDetails(aadhaar) {
    const record = S.records.find((r) => r.aadhaarNumber === aadhaar);
    if (!record) {
      snackbar("Record not found.");
      return;
    }
    const header = `
      <button class="icon-btn" data-close type="button"><span class="material-symbols-outlined">arrow_back</span></button>
      <h2>Record details</h2>`;

    const tile = (icon, label, value, copyable) => `
      <div class="info-tile">
        <span class="material-symbols-outlined">${icon}</span>
        <div class="body"><div class="label">${esc(label)}</div><div class="value">${esc(value || "\u2014")}</div></div>
        ${copyable && value ? `<button class="copy-btn" data-copy="${esc(value)}" type="button"><span class="material-symbols-outlined" style="font-size:18px">content_copy</span></button>` : ""}
      </div>`;

    const body = `
      <div class="card detail-head">
        ${avatarHtml(record, 44)}
        <div>
          <div class="name">${esc(record.name || "Unnamed record")}</div>
          ${record.mobileNumberCorrect ? `<div class="mobile">${esc(record.mobileNumberCorrect)}</div>` : ""}
        </div>
        <div class="pills">
          ${statusChip(record.syncStatus)}
          ${record.relation ? `<span class="pill"><span class="material-symbols-outlined">diversity_3</span>${esc(record.relation)}</span>` : ""}
          ${record.gender ? `<span class="pill"><span class="material-symbols-outlined">wc</span>${esc(genderLabel(record.gender))}</span>` : ""}
        </div>
      </div>

      <div class="section-label">Identity</div>
      <div class="card" style="padding:4px 16px">
        ${tile("confirmation_number", "Application No", record.applicationNo, true)}
        ${tile("person", "Name", record.name, true)}
        ${tile("man", "Name / Father's or Husband's", record.guardianName, false)}
        ${tile("diversity_3", "Relation", record.relation, false)}
        ${tile("wc", "Male / Female", genderLabel(record.gender), false)}
        ${tile("badge", "Aadhaar number", record.aadhaarNumber, true)}
      </div>

      <div class="section-label">Address</div>
      <div class="card" style="padding:4px 16px">
        ${tile("location_on", "Address", record.address, true)}
        ${tile("home_pin", "Address Correct", record.addressCorrect, true)}
      </div>

      <div class="section-label">Bank details</div>
      <div class="card" style="padding:4px 16px">
        ${tile("account_balance", "Bank Name", record.bankName, false)}
        ${tile("numbers", "Account Number", record.accountNumber, true)}
        ${tile("pin", "IFSC Code", record.ifscCode, true)}
      </div>

      <div class="section-label">Contact</div>
      <div class="card" style="padding:4px 16px">
        ${tile("call", "Mobile Number Correct", record.mobileNumberCorrect, true)}
      </div>

      ${record.remarks ? `<div class="section-label">Remarks</div><div class="card" style="padding:16px">${esc(record.remarks)}</div>` : ""}

      <div class="section-label">Timestamps</div>
      <div class="card" style="padding:4px 16px">
        ${tile("add_circle", "Created", fmtDateTime(record.createdAt), false)}
        ${tile("update", "Last updated", fmtDateTime(record.updatedAt), false)}
      </div>

      <div class="spacer"></div>
      <div class="btn-row">
        <button class="btn btn-outlined" id="editBtn" type="button"><span class="material-symbols-outlined">edit</span>Edit</button>
        <button class="btn btn-outlined btn-danger" id="delBtn" type="button"><span class="material-symbols-outlined">delete</span>Delete</button>
      </div>
      <div class="center muted small" style="text-align:center;margin-top:12px;color:var(--on-surface-variant)">Synced: ${esc(record.syncStatus)}</div>`;

    openSheet({ header, body });

    const host = el("sheetHost");
    host.querySelectorAll("[data-copy]").forEach((b) =>
      b.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(b.dataset.copy);
          snackbar("Copied to clipboard.");
        } catch (e) {
          snackbar("Could not copy.");
        }
      })
    );
    el("editBtn").addEventListener("click", () => {
      const current = S.records.find((r) => r.aadhaarNumber === aadhaar);
      openForm(current);
    });
    el("delBtn").addEventListener("click", async () => {
      closeSheet();
      await deleteRecordFlow(aadhaar);
    });
  }

  /* ---- Export ---- */
  const EXPORT_HEADERS = [
    ...FIELDS.map((f) => f.header),
    "Created At",
    "Updated At",
    "Sync Status",
  ];

  function exportRows() {
    return S.records.map((r) => [
      ...FIELDS.map((f) => (f.key === "gender" ? genderLabel(r.gender) : r[f.key] || "")),
      fmtDateTime(r.createdAt),
      fmtDateTime(r.updatedAt),
      r.syncStatus,
    ]);
  }

  function buildWorkbookBlob() {
    const aoa = [EXPORT_HEADERS, ...exportRows()];
    if (window.XLSX) {
      const ws = XLSX.utils.aoa_to_sheet(aoa);
      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, "Records");
      const out = XLSX.write(wb, { bookType: "xlsx", type: "array" });
      return { blob: new Blob([out], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), ext: "xlsx" };
    }
    const csv = aoa
      .map((row) => row.map((cell) => `"${String(cell == null ? "" : cell).replace(/"/g, '""')}"`).join(","))
      .join("\r\n");
    return { blob: new Blob([csv], { type: "text/csv" }), ext: "csv" };
  }

  async function doExport(share) {
    if (!S.records.length) {
      snackbar("There are no records to export yet.");
      return;
    }
    const { blob, ext } = buildWorkbookBlob();
    const filename = `recordvault_${fileStamp(new Date())}.${ext}`;
    const file = new File([blob], filename, { type: blob.type });
    if (share && navigator.canShare && navigator.canShare({ files: [file] })) {
      try {
        await navigator.share({ files: [file], title: "RecordVault export" });
        return;
      } catch (e) {
        if (e.name === "AbortError") return;
      }
    }
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    snackbar(`Exported ${S.records.length} record${S.records.length === 1 ? "" : "s"} to ${filename}.`, 4000);
  }

  /* ---- Wiring ---- */
  function wireGlobal() {
    document.querySelectorAll(".nav-item").forEach((n) => n.addEventListener("click", () => setTab(n.dataset.tab)));
    el("fab").addEventListener("click", () => openForm(null));
    window.addEventListener("scroll", () => {
      el("appbar").classList.toggle("scrolled", window.scrollY > 2);
    });
    window.addEventListener("online", () => { S.online = true; render(); });
    window.addEventListener("offline", () => { S.online = false; render(); });
    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape") closeSheet();
    });
  }

  function init() {
    S.themeMode = localStorage.getItem("rv_theme") || "system";
    applyTheme();
    wireGlobal();
    const hash = location.hash.replace(/^#/, "");
    if (["dashboard", "records", "settings"].includes(hash)) S.tab = hash;
    render();
    loadRecords().then(() => {
      if (hash === "new") openForm(null);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
