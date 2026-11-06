// Squeek Odometer site: plain JSON-RPC, no libraries. Reads go to a public Sepolia RPC so the page works without a
// wallet; only the mint goes through the wallet.
const CFG = window.ODOMETER_CONFIG
const SEL = { mint: '0x1249c58b', idOf: '0xd94fe832', tokenURI: '0xc87b56dd', totalMinted: '0xa2309ff8' }
const MINTED = '0xc9d0543a84d3510329c0783b91576878ceb484e8699944cb5610c3436b3b8e39' // Minted(uint256,address,uint256)
const CHAIN_HEX = '0x' + CFG.chainId.toString(16)
const $ = (id) => document.getElementById(id)
let account = null

// ---------------------------------------------------------------- JSON-RPC and ABI helpers
let rpcId = 0
async function rpc(method, params = []) {
  const r = await fetch(CFG.rpc, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params }) })
  const j = await r.json()
  if (j.error) throw new Error(j.error.message)
  return j.result
}
const word = (n) => BigInt(n).toString(16).padStart(64, '0')
const call = (data) => rpc('eth_call', [{ to: CFG.address, data }, 'latest'])
function decodeString(hex) {
  const h = hex.slice(2)
  const off = Number(BigInt('0x' + h.slice(0, 64))) * 2
  const len = Number(BigInt('0x' + h.slice(off, off + 64)))
  const bytes = new Uint8Array(len)
  for (let i = 0; i < len; i++) bytes[i] = parseInt(h.substr(off + 64 + i * 2, 2), 16)
  return new TextDecoder().decode(bytes)
}
async function token(id) {
  const uri = decodeString(await call(SEL.tokenURI + word(id)))
  return JSON.parse(atob(uri.slice(uri.indexOf(',') + 1)))
}
const trait = (meta, name) => (meta.attributes.find((a) => a.trait_type === name) || {}).value
const km = (meta) => Number(trait(meta, 'Distance (km)')).toFixed(2)

// ---------------------------------------------------------------- the page
function say(text, kind = '') { const m = $('msg'); m.textContent = text; m.className = 'msg ' + kind }

async function showSupply() {
  try { $('supply').textContent = Number(BigInt(await call(SEL.totalMinted))).toLocaleString('en-US') + ' / 9,999 minted' } catch {}
}

async function showMine() {
  if (!account || !CFG.address) return
  const id = Number(BigInt(await call(SEL.idOf + word(account))))
  if (!id) { $('mint').disabled = false; $('mine-caption').textContent = 'Your odometer shows up here after you mint.'; return }
  const meta = await token(id)
  $('mine').src = meta.image
  $('mine-caption').textContent = `#${id} · ${km(meta)} km since your mint · ${trait(meta, 'Stage')} · ${trait(meta, 'Status')}`
  $('mint').disabled = true
  $('mint').textContent = 'Minted'
}

async function showRecent() {
  const box = $('recent')
  if (!CFG.address) { box.innerHTML = '<p class="muted">The contract is not deployed yet.</p>'; return }
  try {
    const head = Number(BigInt(await rpc('eth_blockNumber')))
    const logs = []
    // public RPCs cap a log search, so walk back in 50,000-block steps until there are enough mints
    for (let to = head; to >= CFG.fromBlock && logs.length < 8; to -= 50_000) {
      const from = Math.max(CFG.fromBlock, to - 49_999)
      const part = await rpc('eth_getLogs', [{ address: CFG.address, topics: [MINTED], fromBlock: '0x' + from.toString(16), toBlock: '0x' + to.toString(16) }])
      logs.unshift(...part)
    }
    const ids = logs.map((l) => Number(BigInt(l.topics[1]))).reverse().slice(0, 8)
    if (!ids.length) { box.innerHTML = '<p class="muted">No odometers yet. Be the first.</p>'; return }
    box.innerHTML = ''
    for (const id of ids) {
      const meta = await token(id)
      const card = document.createElement('figure')
      card.className = 'card'
      const img = document.createElement('img')
      img.src = meta.image; img.alt = meta.name; img.width = 160; img.height = 160; img.loading = 'lazy'
      const cap = document.createElement('figcaption')
      cap.textContent = `#${id} · ${km(meta)} km · ${trait(meta, 'Status')}`
      card.append(img, cap)
      box.append(card)
    }
  } catch (e) {
    box.innerHTML = '<p class="muted">Could not read the latest mints right now.</p>'
  }
}

async function showLive() {
  try {
    const s = await (await fetch(CFG.api + '/v1/status')).json()
    const m = s.measurement || {}
    const rpm = (m.rpmMilli || 0) / 1000
    $('live-state').textContent = rpm > 0 ? 'running' : 'napping'
    $('live-state').className = 'v ' + (rpm > 0 ? 'on' : 'off')
    $('live-rpm').textContent = rpm > 0 ? rpm.toFixed(0) + ' rpm' : '0 rpm'
    const anchor = (s.builder || {}).anchor || {}
    $('live-height').textContent = anchor.blockHeight != null ? Number(anchor.blockHeight).toLocaleString('en-US') : '—'
    $('live-work').textContent = m.cumulativeWorkUnits != null ? Number(m.cumulativeWorkUnits).toLocaleString('en-US') + ' turns' : '—'
  } catch {
    $('live-state').textContent = 'unavailable'
  }
}

// ---------------------------------------------------------------- wallet
async function connect() {
  if (!window.ethereum) { say('No wallet found. Install MetaMask or another browser wallet.', 'bad'); return }
  try {
    const [a] = await window.ethereum.request({ method: 'eth_requestAccounts' })
    account = a.toLowerCase()
    $('connect').textContent = a.slice(0, 6) + '…' + a.slice(-4)
    await switchChain()
    await showMine()
    if (!$('mint').disabled) say('')
  } catch (e) { say(e.message || 'The wallet refused.', 'bad') }
}

async function switchChain() {
  const id = await window.ethereum.request({ method: 'eth_chainId' })
  if (id === CHAIN_HEX) return
  await window.ethereum.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: CHAIN_HEX }] })
}

async function mint() {
  if (!account) return connect()
  $('mint').disabled = true
  try {
    await switchChain()
    say('Confirm the mint in your wallet. It is free; you pay only Sepolia gas.')
    const hash = await window.ethereum.request({ method: 'eth_sendTransaction', params: [{ from: account, to: CFG.address, data: SEL.mint }] })
    say('Minting… waiting for Sepolia to include it.')
    let receipt = null
    for (let i = 0; i < 90 && !receipt; i++) {
      receipt = await rpc('eth_getTransactionReceipt', [hash])
      if (!receipt) await new Promise((r) => setTimeout(r, 2000))
    }
    if (!receipt || receipt.status !== '0x1') throw new Error('The mint did not go through. If you already minted, each wallet gets one.')
    say('Minted. Your odometer starts counting now.', 'good')
    await Promise.all([showMine(), showSupply(), showRecent()])
  } catch (e) {
    say(e.message || 'The mint did not go through.', 'bad')
    $('mint').disabled = false
  }
}

function init() {
  $('connect').onclick = connect
  $('mint').onclick = mint
  if (CFG.address) {
    $('mint').disabled = false
    const link = $('contract-link')
    link.href = CFG.explorer + '/address/' + CFG.address
    link.textContent = CFG.address.slice(0, 6) + '…' + CFG.address.slice(-4)
  } else {
    say('The contract is not deployed yet.', 'bad')
  }
  if (CFG.repo) $('repo-link').href = CFG.repo
  showSupply(); showRecent(); showLive()
  setInterval(showLive, 30_000)
  if (window.ethereum) window.ethereum.on?.('accountsChanged', () => location.reload())
}
init()
