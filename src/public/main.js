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
  }
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
  if (buffer.length > 2) {
    return buffer;
  }
  let m = Math.floor(diff / MINUTE);
  if (m > 0) {
    diff -= m * MINUTE;
    buffer += m + 'm';
  }
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

const handleTimes = (nodes) => {
  nodes.forEach(node => handleTime(node));
};

window.onload = () => {
  let nodes = Array.from(document.querySelectorAll('time'));
  handleTimes(nodes);
  window.setInterval(() => handleTimes(nodes), 1000);
}
