// The LED board: a dot-matrix sign drawn on a canvas, fed by app.js with the wheel's live state.
// window.LedBoard.set({ state: 'running' | 'napping' | 'nosignal' | 'loading', km, rpm, block })
;(function () {
  // 5x7 glyphs, one string per row; narrow glyphs use shorter rows
  const G = {
    A: ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
    B: ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
    C: ['01110', '10001', '10000', '10000', '10000', '10001', '01110'],
    D: ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
    E: ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    F: ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
    G: ['01110', '10001', '10000', '10111', '10001', '10001', '01111'],
    H: ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
    I: ['111', '010', '010', '010', '010', '010', '111'],
    J: ['00111', '00010', '00010', '00010', '00010', '10010', '01100'],
    K: ['10001', '10010', '10100', '11000', '10100', '10010', '10001'],
    L: ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
    M: ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
    N: ['10001', '10001', '11001', '10101', '10011', '10001', '10001'],
    O: ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
    P: ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
    Q: ['01110', '10001', '10001', '10001', '10101', '10010', '01101'],
    R: ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
    S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
    T: ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
    U: ['10001', '10001', '10001', '10001', '10001', '10001', '01110'],
    V: ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
    W: ['10001', '10001', '10001', '10101', '10101', '10101', '01010'],
    X: ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
    Y: ['10001', '10001', '10001', '01010', '00100', '00100', '00100'],
    Z: ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
    0: ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
    1: ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
    2: ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
    3: ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
    4: ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
    5: ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
    6: ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
    7: ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
    8: ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
    9: ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
    '.': ['0', '0', '0', '0', '0', '0', '1'],
    ',': ['00', '00', '00', '00', '00', '01', '10'],
    ':': ['0', '0', '1', '0', '1', '0', '0'],
    '-': ['000', '000', '000', '111', '000', '000', '000'],
    '/': ['00001', '00010', '00010', '00100', '01000', '01000', '10000'],
    '!': ['1', '1', '1', '1', '1', '0', '1'],
    ' ': ['00', '00', '00', '00', '00', '00', '00'],
  }
  const C = { off: '#1f1f25', orange: '#f6a63b', cream: '#f3e9cc', grey: '#7d7d88', blue: '#8fa2ff', green: '#7fe08a', rim: '#9a9aa6' }
  const textWidth = (s, k) => [...s].reduce((w, ch) => w + ((G[ch] || G[' '])[0].length + 1) * k, -k)

  const canvas = document.getElementById('led')
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches
  let data = { state: 'loading' }
  let cols = 0, rows = 0, pitch = 0, lit = null, turn = 0, tick = 0, timer = null

  function put(x, y, color) { if (x >= 0 && y >= 0 && x < cols && y < rows) lit[y * cols + x] = color }
  function text(s, x, y, color, k = 1) {
    for (const ch of s) {
      const g = G[ch] || G[' ']
      for (let r = 0; r < 7; r++) for (let c = 0; c < g[r].length; c++) {
        if (g[r][c] !== '1') continue
        for (let i = 0; i < k; i++) for (let j = 0; j < k; j++) put(x + c * k + i, y + r * k + j, color)
      }
      x += (g[0].length + 1) * k
    }
  }
  // a wheel of dots: rim, hub and three spokes that turn with the frame counter
  function wheel(cx, cy, R, turn) {
    for (let a = 0; a < 360; a += 3) {
      const t = (a * Math.PI) / 180
      put(Math.round(cx + R * Math.cos(t)), Math.round(cy + R * Math.sin(t)), C.rim)
    }
    for (let a = 0; a < 360; a += 30) {
      const t = ((a + turn * 10) * Math.PI) / 180
      put(Math.round(cx + (R - 2) * Math.cos(t)), Math.round(cy + (R - 2) * Math.sin(t)), C.grey)
    }
    for (let s = 0; s < 3; s++) {
      const t = ((s * 120 + turn * 10) * Math.PI) / 180
      for (let d = 2; d < R - 2; d++) put(Math.round(cx + d * Math.cos(t)), Math.round(cy + d * Math.sin(t)), C.grey)
    }
    for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) put(cx + i, cy + j, C.orange)
  }

  // the sign's lines, top to bottom: [text, color, scale]
  function lines() {
    const s = data.state
    const big = cols >= 100 ? 2 : 1
    const km = data.km != null ? data.km.toFixed(2) + ' KM' : '--.-- KM'
    return [
      ['SQUEEKTOSHI', C.orange, 1],
      [s === 'running' ? 'IS RUNNING' : s === 'napping' ? 'IS NAPPING' : s === 'nosignal' ? 'NO SIGNAL' : 'TUNING IN',
        s === 'running' ? C.green : s === 'napping' ? C.blue : C.cream, 1],
      ['HAS RUN', C.grey, 1],
      [km, C.cream, textWidth(km, big) <= cols - 4 ? big : 1],
      [(data.rpm != null ? Math.round(data.rpm) : '--') + ' RPM', C.grey, 1],
      ['BLOCK ' + (data.block != null ? data.block.toLocaleString('en-US') : '--'), C.grey, 1],
    ]
  }
  const GAP = 2, PAD = 2
  const height = (ls) => ls.reduce((h, l) => h + 7 * l[2] + GAP, 2 * PAD - GAP)

  function compose(ls) {
    lit = new Array(cols * rows).fill(null)
    let y = PAD, left = 0
    for (const [s, color, k] of ls) {
      text(s, PAD, y, color, k)
      left = Math.max(left, textWidth(s, k))
      y += 7 * k + GAP
    }
    // the wheel sits on the right when there is room for it; it stands still while he naps
    const R = Math.min(17, Math.floor((rows - 6) / 2))
    if (cols - left - PAD - 6 >= 2 * R + 4) {
      wheel(cols - R - 4, Math.floor(rows / 2), R, turn)
      if (data.state === 'napping' && tick % 2 === 0) text('Z', cols - 9, 1, C.blue)
    }
  }

  function draw() {
    const dpr = window.devicePixelRatio || 1
    const w = canvas.clientWidth
    if (!w) return
    cols = Math.max(48, Math.floor(w / (w >= 700 ? 6.5 : w >= 520 ? 6 : 5)))
    pitch = w / cols
    const ls = lines()
    rows = height(ls)
    const h = rows * pitch
    canvas.style.height = h + 'px'
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr)
      canvas.height = Math.round(h * dpr)
    }
    compose(ls)
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, w, h)
    const rad = pitch * 0.36
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
      ctx.fillStyle = lit[y * cols + x] || C.off
      ctx.beginPath()
      ctx.arc((x + 0.5) * pitch, (y + 0.5) * pitch, rad, 0, 6.2832)
      ctx.fill()
    }
  }

  // the wheel steps faster as he runs: one step every 300 ms at a crawl, 60 ms at full tilt; asleep, only the Z blinks
  function loop() {
    clearTimeout(timer)
    if (still || (data.state !== 'running' && data.state !== 'napping')) return
    const running = data.state === 'running'
    const ms = running ? Math.max(60, 300 - (data.rpm || 0) * 3) : 900
    timer = setTimeout(() => { if (running) turn++; tick++; draw(); loop() }, ms)
  }

  function label() {
    const s = data.state
    const words = s === 'running' ? 'is running' : s === 'napping' ? 'is napping' : s === 'nosignal' ? 'cannot be reached' : 'is loading'
    const km = data.km != null ? `, ${data.km.toFixed(2)} km run so far` : ''
    canvas.setAttribute('aria-label', `LED board: Squeektoshi ${words}${km}.`)
  }

  window.LedBoard = {
    set(next) { data = { ...data, ...next }; label(); draw(); loop() },
  }
  new ResizeObserver(() => draw()).observe(canvas)
  label()
  draw()
})()
