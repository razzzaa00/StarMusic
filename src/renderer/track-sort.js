const TRACK_SORT_MODES = ['manual', 'added-desc', 'added-asc', 'title-asc', 'artist-asc', 'duration-asc'];

const TRACK_SORT_COMPARATORS = (() => {
  const collator = typeof Intl !== 'undefined' ? new Intl.Collator(undefined, { sensitivity: 'base', numeric: true }) : null;

  function compareText(a, b) {
    const x = typeof a === 'string' ? a.trim() : '';
    const y = typeof b === 'string' ? b.trim() : '';
    if (!x || !y) return x ? -1 : y ? 1 : 0;
    return collator ? collator.compare(x, y) : x.toLowerCase().localeCompare(y.toLowerCase());
  }

  function durationSeconds(t) {
    const d = t && t.duration;
    if (typeof d === 'number') return d > 0 ? d : 0;
    if (typeof d === 'string' && d.trim()) {
      const secs = d.split(':').reduce((acc, part) => acc * 60 + (parseFloat(part) || 0), 0);
      return secs > 0 ? secs : 0;
    }
    return 0;
  }

  const COMPARATORS = {
    'added-desc': (a, b) => addedAt(b) - addedAt(a),
    'added-asc': (a, b) => addedAt(a) - addedAt(b),
    'title-asc': (a, b) => compareText(a && a.title, b && b.title),
    'artist-asc': (a, b) => compareText(a && a.artist, b && b.artist),
    'duration-asc': (a, b) => {
      const x = durationSeconds(a);
      const y = durationSeconds(b);
      if (!x || !y) return x ? -1 : y ? 1 : 0;
      return x - y;
    }
  };

  function addedAt(t) {
    return t && typeof t.addedAt === 'number' ? t.addedAt : 0;
  }

  return COMPARATORS;
})();

function sortTracks(tracks, mode) {
  const list = Array.isArray(tracks) ? tracks.slice() : [];
  const cmp = TRACK_SORT_COMPARATORS[mode];
  return cmp ? list.sort(cmp) : list;
}

function backfillAddedAt(tracks, newestFirst) {
  if (!Array.isArray(tracks)) return tracks;
  const now = Date.now();
  let changed = false;
  const list = tracks.map((t, i) => {
    if (!t || typeof t.addedAt === 'number') return t;
    changed = true;
    return { ...t, addedAt: now - (newestFirst ? i : tracks.length - i) * 1000 };
  });
  return changed ? list : tracks;
}

if (typeof module !== 'undefined') module.exports = { TRACK_SORT_MODES, sortTracks, backfillAddedAt };
