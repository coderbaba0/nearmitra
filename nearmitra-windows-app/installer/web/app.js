// NearMitra Standalone Setup Wizard JS
let currentStep = 1;
let installerInfo = null;

document.addEventListener("DOMContentLoaded", () => {
  fetchInstallerInfo();
});

async function fetchInstallerInfo() {
  try {
    const res = await fetch("/api/installer/info");
    if (res.ok) {
      installerInfo = await res.json();
      if (installerInfo.app_version) {
        document.getElementById("sidebarVersion").textContent = `v${installerInfo.app_version} Standalone`;
      }
      const publisher=document.getElementById("sidebarPublisher");
      if(publisher && installerInfo.publisher) publisher.textContent=installerInfo.publisher;
      if (installerInfo.install_path) {
        document.getElementById("txtInstallPath").value = installerInfo.install_path;
      }
    }
  } catch (err) {
    console.warn("Could not load installer info:", err);
  }
}

function toggleEulaAgree(checked) {
  const btnNext = document.getElementById("btnStep1Next");
  if (btnNext) {
    btnNext.disabled = !checked;
  }
}

function goToStep(step) {
  currentStep = step;

  // Update step nav
  for (let i = 1; i <= 4; i++) {
    const navEl = document.getElementById(`stepNav${i}`);
    const stageEl = document.getElementById(`stage${i}`);

    if (navEl) {
      navEl.classList.remove("active", "completed");
      if (i === step) {
        navEl.classList.add("active");
      } else if (i < step) {
        navEl.classList.add("completed");
      }
    }

    if (stageEl) {
      if (i === step) {
        stageEl.classList.add("active");
      } else {
        stageEl.classList.remove("active");
      }
    }
  }
}

function appendLog(msg) {
  const logBox = document.getElementById("installLogBox");
  if (logBox) {
    const line = document.createElement("div");
    line.textContent = `[${new Date().toLocaleTimeString()}] ${msg}`;
    logBox.appendChild(line);
    logBox.scrollTop = logBox.scrollHeight;
  }
}

function updateProgress(percent, statusText) {
  const bar = document.getElementById("installProgressBar");
  const pct = document.getElementById("installPercent");
  const status = document.getElementById("installStatusText");

  if (bar) bar.style.width = `${percent}%`;
  if (pct) pct.textContent = `${percent}%`;
  if (status && statusText) status.textContent = statusText;
}

async function startInstallation() {
  goToStep(3);

  const chkDesktop = document.getElementById("chkDesktop")?.checked ?? true;
  const chkStartMenu = document.getElementById("chkStartMenu")?.checked ?? true;
  const chkAutostart = document.getElementById("chkAutostart")?.checked ?? true;

  appendLog("Starting NearMitra installation process...");
  updateProgress(15, "Stopping running NearMitra instances (if any)...");

  try {
    // Step animation

    updateProgress(35, "Extracting NearMitra core binaries & embedded assets...");
    appendLog("Target: " + (installerInfo?.install_path || "%LOCALAPPDATA%\\Programs\\NearMitra"));

    const payload = {
      desktop_shortcut: chkDesktop,
      start_menu: chkStartMenu,
      autostart: chkAutostart,
      private_network: document.getElementById("chkPrivateNetwork")?.checked ?? true
    };

    updateProgress(65, "Writing executable files and icons...");
    appendLog("Configuring shortcuts and Windows app registration...");

    const response = await fetch("/api/installer/execute", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    const result = await response.json();

    if (result.success) {
      if(result.warning){appendLog(result.warning);const note=document.getElementById("finishWarning");if(note)note.textContent=result.warning;}
      updateProgress(90, "Finalizing installation...");
      appendLog("Installation successful: " + (result.message || "All components installed."));


      updateProgress(100, "Completed!");
      goToStep(4);
    } else {
      appendLog("ERROR: " + (result.error || "Installation failed"));
      currentStep=2;updateProgress(0, "Installation Failed");goToStep(2);
      alert("Installation Error: " + (result.error || "Unknown error"));
    }
  } catch (err) {
    goToStep(2);appendLog("Network/Execution error: " + err.message);
    alert("Installation Error: " + err.message);
  }
}

async function finishInstaller() {
 const launchNow=document.getElementById('chkLaunchApp')?.checked ?? true;
 try {const response=await fetch('/api/installer/finish',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({launch_now:launchNow})});if(!response.ok)throw new Error(await response.text());window.close();}
 catch(error){alert('Could not finish setup: '+error.message);}
}
async function closeInstaller() {
 if(currentStep===3){alert('Please wait for installation to finish.');return;}
 try {const response=await fetch('/api/installer/cancel',{method:'POST'});if(!response.ok)throw new Error(await response.text());window.close();}
 catch(error){alert(error.message);}
}
