const MINUTE = 60;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const formatDiff = (diff) => {
  if (diff == 0) {
    return '0s';
  }
  let buffer = '';
  if (diff < 0) {
    buffer += '-'
    diff *= -1;
  }
  let trunc1 = diff > DAY;
  let trunc2 = diff > HOUR;
  let d = Math.floor(diff / DAY);
  if (d > 0) {
    diff -= d * DAY;
    buffer += d + 'd';
  }
  let h = Math.floor(diff / HOUR);
  if (h > 0) {
    diff -= h * HOUR;
    buffer += h + 'h';
  }
  if (trunc1) return buffer;
  let m = Math.floor(diff / MINUTE);
  if (m > 0) {
    diff -= m * MINUTE;
    buffer += m + 'm';
  }
  if (trunc2) return buffer;
  buffer += diff + 's';

  return buffer;
};

const handleTime = (node) => {
  let time = new Date(node.dateTime);
  if (node.getAttribute('relative') != null) {
    let now = new Date();
    node.innerText = formatDiff(Math.round((now.getTime() - time.getTime()) / 1000));
  } else if (!node.innerText) {
   node.innerText = time.toLocaleString('en-AU', {hour12: false}); 
  }
};

const handleTimes = nodes => nodes.forEach(handleTime);

async function do_fetch(action, button) {
  try {
    let resp = await fetch(action, {
      method: 'POST',
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(button.dataset)
    })
    let data;
    if (resp.headers.get("content-type") == 'application/json') {
      data = await resp.json();
    } else {
      let msg = await resp.text();
      throw msg;
    }
    let originalText = button.innerText;
    button.innerText = data.text;
    if (data.invalidate) {
      button.dataset.action = null;
    } else {
      window.setTimeout(() => { button.innerText = originalText; }, 2000);
    }
  } catch (err) {
    console.error(err);
    button.innerText = '‼️';
    button.dataset.action = null;
    alert(err);
  }
  button.classList.remove('in-progress');
}

const make_action_listener = button => () => {
  let action = button.dataset.action;
  if (!action) { return; }
  if (!confirm("Really do " + action + "?")) { return; }
  button.classList.add('in-progress');
  button.innerText = '🕖';
  do_fetch(action, button);
};

function filter(value) {
  let search = value.toLowerCase().trim();
  let containers = document.querySelectorAll('section.container');
  for (let container of containers) {
    if (!search) {
      container.classList.remove('hidden');
      continue;
    }
    if (container.dataset.search.toLowerCase().indexOf(search) >= 0) {
      container.classList.remove('hidden');
    } else {
      container.classList.add('hidden');
    }
  }
}

window.onload = () => {
  let nodes = Array.from(document.querySelectorAll('time'));
  handleTimes(nodes);
  window.setInterval(() => handleTimes(nodes), 1000);
  Array.from(document.querySelectorAll('button.action')).forEach(button =>
    button.addEventListener('click', make_action_listener(button)));
  let search = document.getElementById('search');
  let debounce = null;
  search.addEventListener('input', () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => filter(search.value), 50);
  });
}
