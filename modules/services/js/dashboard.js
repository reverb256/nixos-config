// Host Dashboard JavaScript - Safe DOM manipulation to avoid XSS

function setTextContent(id, text) {
  const el = document.getElementById(id);
  if (el) el.textContent = text;
}

function loadServices() {
  const services = /* SERVICES_PLACEHOLDER */;

  const servicesList = document.getElementById('services');
  if (servicesList && Object.keys(services).length > 0) {
    servicesList.innerHTML = "";
    Object.values(services).forEach(function(service) {
      const li = document.createElement('li');
      li.className = 'service-item';

      const nameSpan = document.createElement('span');
      nameSpan.className = 'service-name';
      nameSpan.textContent = service.name;

      const statusSpan = document.createElement('span');
      statusSpan.className = 'service-status ' + (service.active ? 'active' : 'inactive');
      statusSpan.textContent = service.active ? '● Running' : '○ Stopped';

      li.appendChild(nameSpan);
      li.appendChild(statusSpan);
      servicesList.appendChild(li);
    });
  } else {
    if (servicesList) {
      servicesList.innerHTML = '<li class="service-item"><span class="service-name">No services configured</span></li>';
    }
  }
}

function updateUptime() {
  fetch('/api/uptime')
    .then(function(r) { return r.text(); })
    .then(function(text) { setTextContent('uptime', text); })
    .catch(function() { setTextContent('uptime', 'Unknown'); });
}

// Initialize
document.addEventListener('DOMContentLoaded', function() {
  loadServices();
  updateUptime();
  setInterval(updateUptime, 30000);
});
