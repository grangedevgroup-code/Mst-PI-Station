// Mst-PI-Station Dashboard — core JS

// Auto-refresh status every 30s
let statusRefreshTimer;
function startAutoRefresh(intervalMs = 30000) {
    statusRefreshTimer = setInterval(() => {
        fetch('/api/status')
            .then(r => r.json())
            .then(data => updateHealthIndicator(data.healthy))
            .catch(() => {});
    }, intervalMs);
}

function updateHealthIndicator(healthy) {
    const dot = document.getElementById('health-dot');
    if (!dot) return;
    const span = dot.querySelector('span:first-child');
    const label = dot.querySelector('span:last-child');
    if (span) {
        span.className = `w-2 h-2 rounded-full ${healthy ? 'bg-green-500' : 'bg-red-500'} animate-pulse`;
    }
    if (label) {
        label.className = healthy ? 'text-green-400' : 'text-red-400';
        label.textContent = healthy ? 'healthy' : 'degraded';
    }
}

document.addEventListener('DOMContentLoaded', () => {
    startAutoRefresh();
});
