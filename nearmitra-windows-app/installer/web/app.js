/* ==========================================================
   NearMitra Setup Wizard Client Engine
   ========================================================== */
let currentStep = 1;
const totalSteps = 5;

document.addEventListener("DOMContentLoaded", async () => {
  try {
    const res = await fetch("/api/installer/info");
    if (res.ok) {
      const data = await res.json();
      const txt = document.getElementById("txtInstallPath");
      if (txt && data.install_path) {
        txt.value = data.install_path;
      }
    }
  } catch (e) {}
  updateWizardUI();
});

function updateWizardUI() {
  // Update step visibility
  for (let i = 1; i <= totalSteps; i++) {
    const el = document.getElementById(`step${i}`);
    if (el) el.classList.toggle("active", i === currentStep);

    const dot = document.getElementById(`dot${i}`);
    if (dot) {
      dot.classList.toggle("active", i === currentStep);
      dot.classList.toggle("completed", i < currentStep);
    }
  }

  const btnBack = document.getElementById("btnBack");
  const btnNext = document.getElementById("btnNext");
  const btnCancel = document.getElementById("btnCancel");

  if (btnBack) btnBack.style.display = (currentStep > 1 && currentStep < 4) ? "inline-block" : "none";
  if (btnCancel) btnCancel.style.display = (currentStep < 4) ? "inline-block" : "none";

  if (btnNext) {
    if (currentStep === 1) {
      btnNext.innerText = "Next \u2192";
      btnNext.disabled = false;
      btnNext.className = "btn btn-primary";
    } else if (currentStep === 2) {
      const accepted = document.getElementById("chkAcceptTerms").checked;
      btnNext.innerText = "Agree & Continue \u2192";
      btnNext.disabled = !accepted;
      btnNext.className = "btn btn-primary";
    } else if (currentStep === 3) {
      btnNext.innerText = "Install NearMitra";
      btnNext.disabled = false;
      btnNext.className = "btn btn-primary";
    } else if (currentStep === 4) {
      btnNext.style.display = "none";
    } else if (currentStep === 5) {
      btnNext.style.display = "inline-block";
      btnNext.innerText = "Finish";
      btnNext.className = "btn btn-primary";
    }
  }
}

function onTermsChanged(checked) {
  const btnNext = document.getElementById("btnNext");
  if (currentStep === 2 && btnNext) {
    btnNext.disabled = !checked;
  }
}

function goNextStep() {
  if (currentStep === 3) {
    // Start installation
    currentStep = 4;
    updateWizardUI();
    runInstallation();
  } else if (currentStep === 5) {
    // Finish setup
    finishSetup();
  } else {
    currentStep++;
    updateWizardUI();
  }
}

function goPrevStep() {
  if (currentStep > 1 && currentStep < 4) {
    currentStep--;
    updateWizardUI();
  }
}

async function runInstallation() {
  const chkDesktop = document.getElementById("chkDesktopShortcut").checked;
  const chkStartMenu = document.getElementById("chkStartMenu").checked;
  const chkAutostart = document.getElementById("chkAutostart").checked;

  const progressBar = document.getElementById("installProgressBar");
  const progressPct = document.getElementById("installProgressPct");
  const statusLbl = document.getElementById("lblInstallStatus");
  const detailLbl = document.getElementById("lblInstallDetail");
  const logBox = document.getElementById("installLogBox");

  function addLog(msg) {
    if (logBox) {
      const line = document.createElement("div");
      line.className = "log-line";
      line.innerText = `[${new Date().toLocaleTimeString()}] ${msg}`;
      logBox.appendChild(line);
      logBox.scrollTop = logBox.scrollHeight;
    }
  }

  function setProgress(pct, status, detail) {
    if (progressBar) progressBar.style.width = `${pct}%`;
    if (progressPct) progressPct.innerText = `${pct}%`;
    if (status && statusLbl) statusLbl.innerText = status;
    if (detail && detailLbl) detailLbl.innerText = detail;
  }

  setProgress(15, "Preparing Installation Directory...", "Stopping running instances...");
  addLog("Closing existing NearMitra background processes...");

  try {
    const payload = {
      desktop_shortcut: chkDesktop,
      start_menu: chkStartMenu,
      autostart: chkAutostart
    };

    setProgress(40, "Extracting Core Binaries...", "Writing NearMitra.exe & system assets...");
    addLog("Extracting NearMitra.exe (100% P2P Engine, WebRTC CCTV, IoT)...");

    const res = await fetch("/api/installer/execute", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    setProgress(75, "Creating Shortcuts & Registering...", "Generating desktop and start menu icons...");
    addLog("Registering in Windows 11 Installed Apps & Control Panel...");

    const data = await res.json();
    if (data.success) {
      setProgress(100, "Installation Complete!", "NearMitra is ready.");
      addLog("Installation completed successfully without errors.");

      setTimeout(() => {
        currentStep = 5;
        updateWizardUI();
      }, 700);
    } else {
      statusLbl.innerText = "Installation Failed";
      detailLbl.innerText = data.error || "An error occurred during setup.";
      addLog(`Error: ${data.error}`);
    }
  } catch (err) {
    statusLbl.innerText = "Installation Error";
    detailLbl.innerText = err.message;
    addLog(`Fatal Error: ${err.message}`);
  }
}

async function finishSetup() {
  const launchNow = document.getElementById("chkLaunchNow").checked;
  try {
    await fetch("/api/installer/finish", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ launch_now: launchNow })
    });
  } catch (e) {}

  setTimeout(() => {
    window.close();
  }, 300);
}

function cancelSetup() {
  if (confirm("Are you sure you want to cancel NearMitra installation?")) {
    fetch("/api/installer/cancel", { method: "POST" });
    window.close();
  }
}
