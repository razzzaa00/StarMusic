const TRACK_SORT_MODES = ['manual', 'added-desc', 'added-asc'];

function sortTracks(tracks, mode) {
  const list = Array.isArray(tracks) ? tracks.slice() : [];
  if (mode !== 'added-desc' && mode !== 'added-asc') return list;
  const dir = mode === 'added-desc' ? -1 : 1;
  return list.sort((a, b) => {
    const at = a && typeof a.addedAt === 'number' ? a.addedAt : 0;
    const bt = b && typeof b.addedAt === 'number' ? b.addedAt : 0;
    if (at === bt) return 0;
    return at < bt ? -dir : dir;
  });
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
