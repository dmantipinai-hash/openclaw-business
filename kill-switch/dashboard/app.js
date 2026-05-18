// ═══ Kill Switch Dashboard — логика ═══

const WATCHDOG_URL = "/api";  // nginx проксирует к watchdog
const POLL_INTERVAL = 10000;  // 10 секунд

let pendingAction = null;

// ═══ Инициализация ═══

document.addEventListener("DOMContentLoaded", () => {
    refreshStatus();
    refreshLogs();
    setInterval(refreshStatus, POLL_INTERVAL);
    setInterval(refreshLogs, 30000); // логи реже
});

// ═══ API запросы ═══

async function apiGet(path) {
    try {
        const resp = await fetch(`${WATCHDOG_URL}${path}`);
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        return await resp.json();
    } catch (e) {
        console.error("API error:", e);
        document.getElementById("connectionStatus").className = "status-dot dead";
        return null;
    }
}

async function apiPost(path, body = {}) {
    try {
        const resp = await fetch(`${WATCHDOG_URL}${path}`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body)
        });
        return await resp.json();
    } catch (e) {
        console.error("API error:", e);
        return { error: e.message };
    }
}

// ═══ Обновление статуса ═══

async function refreshStatus() {
    const data = await apiGet("/status");
    if (!data) return;

    document.getElementById("connectionStatus").className = "status-dot alive";
    document.getElementById("lastUpdate").textContent = formatTime(data.timestamp);

    const gateways = data.gateways || [];
    updateStats(gateways);
    renderGateways(gateways);
}

function updateStats(gateways) {
    const alive = gateways.filter(g => g.status === "alive");
    const dead = gateways.filter(g => g.status !== "alive");
    const totalAgents = gateways.reduce((sum, g) => sum + (g.agents || []).length, 0);
    const totalSessions = gateways.reduce((sum, g) => sum + (g.sessions || []).length, 0);

    document.querySelector("#statTotal .stat-value").textContent = gateways.length;
    document.querySelector("#statAlive .stat-value").textContent = alive.length;
    document.querySelector("#statDead .stat-value").textContent = dead.length;
    document.querySelector("#statAgents .stat-value").textContent = totalAgents;
    document.querySelector("#statSessions .stat-value").textContent = totalSessions;
}

function renderGateways(gateways) {
    const container = document.getElementById("gatewaysList");

    if (gateways.length === 0) {
        container.innerHTML = '<div class="gateway-card"><p style="color:var(--text-muted)">Нет настроенных Gateway-хостов</p></div>';
        return;
    }

    container.innerHTML = gateways.map(gw => {
        const statusClass = gw.status || "unknown";
        const statusLabel = {
            alive: "● Active",
            dead: "● Offline",
            timeout: "● Timeout",
            error: "● Error"
        }[gw.status] || "● Unknown";

        const agents = gw.agents || [];
        const sessions = gw.sessions || [];
        const cronJobs = gw.cron_jobs || [];

        return `
            <div class="gateway-card status-${statusClass}">
                <div class="gateway-header">
                    <div>
                        <div class="gateway-name">${escapeHtml(gw.name || gw.host)}</div>
                        <div class="gateway-host">${escapeHtml(gw.host)}:${gw.port}</div>
                    </div>
                    <div class="gateway-status">
                        <span class="status-dot ${statusClass}"></span>
                        <span class="label ${statusClass}">${statusLabel}</span>
                    </div>
                </div>
                ${gw.error ? `<div style="color:var(--red);font-size:13px;margin-bottom:8px">⚠️ ${escapeHtml(gw.error)}</div>` : ""}
                <div class="gateway-details">
                    <div class="detail-item">
                        <div class="detail-label">Агенты</div>
                        <div class="detail-value">${agents.length}</div>
                    </div>
                    <div class="detail-item">
                        <div class="detail-label">Сессии</div>
                        <div class="detail-value">${sessions.length}</div>
                    </div>
                    <div class="detail-item">
                        <div class="detail-label">Cron-задачи</div>
                        <div class="detail-value">${cronJobs.length}</div>
                    </div>
                </div>
                ${agents.length > 0 ? renderAgentsList(agents) : ""}
                <div class="gateway-actions">
                    <button class="btn btn-danger" onclick="killGateway('${escapeHtml(gw.host)}')">
                        🛑 Остановить
                    </button>
                    <button class="btn" onclick="restartGateway('${escapeHtml(gw.host)}')">
                        🔄 Перезапустить
                    </button>
                </div>
                <div style="font-size:11px;color:var(--text-muted);margin-top:8px">
                    Последняя проверка: ${gw.last_check ? formatTime(gw.last_check) : "—"}
                </div>
            </div>
        `;
    }).join("");
}

function renderAgentsList(agents) {
    if (agents.length === 0) return "";

    const items = agents.slice(0, 5).map(a => {
        const name = a.name || a.id || a.agentId || "?";
        return `<span style="background:var(--bg);padding:2px 8px;border-radius:4px;font-size:12px">${escapeHtml(name)}</span>`;
    }).join(" ");

    const more = agents.length > 5 ? `<span style="color:var(--text-muted);font-size:12px">+${agents.length - 5} ещё</span>` : "";

    return `<div style="display:flex;gap:4px;flex-wrap:wrap;margin-bottom:8px">${items} ${more}</div>`;
}

// ═══ Действия ═══

function emergencyKillAll() {
    showConfirmModal(
        "🛑 EMERGENCY KILL ALL",
        "Это остановит ВСЕ Gateway и ВСЕХ агентов на ВСЕХ хостах. Все активные сессии будут прерваны.",
        "KILL",
        async () => {
            const btn = document.getElementById("killAllBtn");
            btn.disabled = true;
            btn.textContent = "⏳ ОСТАНОВКА...";

            const result = await apiPost("/kill-all", {
                operator: "dashboard",
                reason: "emergency kill all"
            });

            btn.disabled = false;
            btn.textContent = "🛑 ОСТАНОВИТЬ ВСЕХ";

            refreshStatus();
            refreshLogs();

            const killed = (result.results || []).filter(r => r.success).length;
            const total = (result.results || []).length;
            alert(`Остановлено: ${killed}/${total} Gateway`);
        }
    );
}

function killGateway(host) {
    showConfirmModal(
        "Остановить Gateway",
        `Остановить OpenClaw Gateway на ${host}? Все агенты и сессии будут прерваны.`,
        "STOP",
        async () => {
            const result = await apiPost(`/gateways/${host}/kill`, {
                operator: "dashboard",
                reason: "manual kill"
            });
            refreshStatus();
            refreshLogs();

            if (result.success) {
                alert(`Gateway ${host} остановлен`);
            } else {
                alert(`Ошибка: ${result.error || "неизвестная ошибка"}`);
            }
        }
    );
}

async function restartGateway(host) {
    showConfirmModal(
        "Перезапустить Gateway",
        `Перезапустить OpenClaw Gateway на ${host}?`,
        "START",
        async () => {
            const result = await apiPost(`/gateways/${host}/restart`, {
                operator: "dashboard"
            });
            refreshStatus();
            refreshLogs();

            if (result.success) {
                alert(`Gateway ${host} перезапускается`);
            } else {
                alert(`Ошибка: ${result.error || "неизвестная ошибка"}`);
            }
        }
    );
}

// ═══ Логи ═══

async function refreshLogs() {
    const data = await apiGet("/logs");
    if (!data || !data.logs) return;

    const container = document.getElementById("logsList");
    container.innerHTML = data.logs.map(line => {
        const isKill = line.includes("KILL");
        return `<div class="log-entry ${isKill ? 'log-kill' : ''}">${escapeHtml(line)}</div>`;
    }).reverse().join("");
}

// ═══ Модальное окно ═══

function showConfirmModal(title, message, confirmWord, action) {
    document.getElementById("confirmTitle").textContent = title;
    document.getElementById("confirmMessage").textContent = message;
    document.getElementById("confirmWord").textContent = confirmWord;
    document.getElementById("confirmInput").value = "";

    const inputGroup = document.getElementById("confirmInputGroup");
    inputGroup.style.display = "block";

    pendingAction = action;
    document.getElementById("confirmModal").classList.remove("hidden");

    setTimeout(() => document.getElementById("confirmInput").focus(), 100);
}

function hideModal() {
    document.getElementById("confirmModal").classList.add("hidden");
    pendingAction = null;
}

async function confirmAction() {
    const input = document.getElementById("confirmInput").value.trim().toUpperCase();
    const word = document.getElementById("confirmWord").textContent.toUpperCase();

    if (input !== word) {
        document.getElementById("confirmInput").style.borderColor = "var(--red)";
        return;
    }

    hideModal();
    if (pendingAction) {
        await pendingAction();
        pendingAction = null;
    }
}

// Enter для подтверждения
document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") hideModal();
    if (e.key === "Enter" && !document.getElementById("confirmModal").classList.contains("hidden")) {
        confirmAction();
    }
});

// ═══ Утилиты ═══

function formatTime(iso) {
    try {
        return new Date(iso).toLocaleTimeString("ru-RU");
    } catch {
        return iso;
    }
}

function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
}
