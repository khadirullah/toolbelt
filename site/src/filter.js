// Narrow the command list on the home page as you type. Every word must appear in the name, the one-liner or the
// group. Without JavaScript the box stays hidden and the full list shows.
(function () {
  var box = document.getElementById('filter-box');
  var input = document.getElementById('filter');
  var none = document.getElementById('nomatch');
  if (!box || !input) return;
  box.hidden = false;
  var groups = [].slice.call(document.querySelectorAll('#commands .group'));

  function apply() {
    var words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    var shown = 0;
    groups.forEach(function (group) {
      var name = group.querySelector('h3').textContent.toLowerCase();
      var inGroup = 0;
      [].forEach.call(group.querySelectorAll('li'), function (li) {
        var text = name + ' ' + li.textContent.toLowerCase();
        var hit = words.every(function (w) { return text.indexOf(w) !== -1; });
        li.hidden = !hit;
        if (hit) inGroup++;
      });
      group.hidden = inGroup === 0;
      shown += inGroup;
    });
    none.hidden = shown > 0;
  }

  input.addEventListener('input', apply);
  input.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      var first = document.querySelector('#commands li:not([hidden]) a');
      if (first) location.href = first.href;
    } else if (e.key === 'Escape') {
      input.value = '';
      apply();
    }
  });
  document.addEventListener('keydown', function (e) {
    var tag = e.target.tagName;
    if (e.key === '/' && tag !== 'INPUT' && tag !== 'TEXTAREA' && !e.ctrlKey && !e.metaKey) {
      e.preventDefault();
      input.focus();
    }
  });
  apply();   // the back button can bring a typed value back
})();
