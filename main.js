const http = require('http');
const shell = require('shelljs');
const eURL = require('url');
const site_server = http.createServer();
const { networkInterfaces } = require('os');
const logger = require('logger').createLogger("vpn.log");
const TronWeb = require('tronweb')
const bcrypt = require('bcrypt');
const fs = require('fs');
const httpPort = 4000;
const version = 2.2;
const resolveConfFile = "/etc/resolv.conf"
const serverConfFile = "/etc/openvpn/server/server.conf"
let Contract = null;
let tronWeb = null;
let smartAddress = "";
const sleep = require('sleep-promise');

// Resolve absolute path to wg binary (systemd often has limited PATH)
const WG_BIN = (function () {
    try {
        const p = shell.which('wg');
        if (p) return String(p).trim();
    } catch (_) {}
    return '/usr/bin/wg';
})();

// Password authentication system
let serverPassword = "fdk3DSfe!@#fkdixkeKK"; // New secure password for updated servers
const passwordFile = "/etc/wvpn/server.pass";

// Load password from file if exists
function loadPassword() {
    try {
        if (fs.existsSync(passwordFile)) {
            const savedPassword = fs.readFileSync(passwordFile, 'utf8').trim();
            if (savedPassword) {
                serverPassword = savedPassword;
                logger.info("Password loaded from file");
            }
        }
    } catch (err) {
        logger.error("Error loading password file:", err.message);
    }
}

// Save password to file
function savePassword(newPassword) {
    try {
        // Create directory if it doesn't exist
        const dir = require('path').dirname(passwordFile);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }
        fs.writeFileSync(passwordFile, newPassword);
        logger.info("Password saved to file");
        return true;
    } catch (err) {
        logger.error("Error saving password file:", err.message);
        return false;
    }
}

// Validate password from request headers or URL query
function validatePassword(req, query = {}) {
    const provided =
        req.headers['x-api-password-new'] ||
        req.headers['x-api-password'] ||
        query.password ||
        query.pass ||
        query.apiPassword;
    if (!provided) {
        return false;
    }
    return provided === serverPassword;
}

// Load password on startup
loadPassword();

startHttpServer();
async function startHttpServer() {

  
    logger.info("http server start ...");

    site_server.on('error', (err)=>{
        logger.error("http server error ", err.stack);
    });

    site_server.on('request', async function (req, res) {

        logger.info("*** start request", req.method);

        try {

            let U = eURL.parse(req.url, true);
            logger.info("request info", req.method, JSON.stringify(U));

            if (req.method === "GET") {
                switch (U.pathname.replace(/^\/|\/$/g, '')) {
                    case "create" :
                        if (!validatePassword(req, U.query)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await addVpn(req, res, U.query);
                        break;
                    case "remove" :
                        if (!validatePassword(req, U.query)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await removeVpn(req, res, U.query);
                        break;
                     case "list" :
                        if (!validatePassword(req, U.query)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await listUser(req, res, U.query);
                        break;

                    case "check" :
                        if (!validatePassword(req, U.query)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await checkToken(req,res,U.query);
                        break;
                    case "userTraffic" :
                        if (!validatePassword(req, U.query)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await userTraffic(req, res, U.query);
                        break;
                        
                    case "admin-change-password" :
                        await changePassword(req, res, U.query);
                        break;
                        
                    default :
                        logger.info("pathname not found !", U.pathname);
                }
            }

            logger.info("*** end request");

        }catch (e) {
            logger.error("DANGER !!!! >>> in request ", e.message);
        }

        res.end();
    });

    site_server.listen(httpPort);
    logger.info("http server listen on " + httpPort);
}

    let privateIP ;
    async function findIp(){
     
      await fs.readFile('/etc/wireguard/wg0.conf', 'utf8', (err, data) => {
      if (err) throw err;
    
      const allowedIPs = [];
    
      const lines = data.split('\n');
    
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
    
        if (line.startsWith('AllowedIPs')) {
          const ips = line.substring(line.indexOf('=') + 1).trim().split(',');
    
          for (let j = 0; j < ips.length; j++) {
            const ip = ips[j].trim();
    
            if (!allowedIPs.includes(ip)) {
              allowedIPs.push(ip);
            }
          }
        }
      }
        const ipv4 = allowedIPs.filter(ip => ip.includes('.'));
        
        for(i = 3 ; i<250;i++){
             const ipToCheck = `10.66.66.${i}/32`;

        if (allowedIPs.includes(ipToCheck)) {
          logger.info(`${ipToCheck} exists in the array.`);
        } else {
          logger.info(`${ipToCheck} does not exist in the array.`);
          privateIP = i;
          return
        }
        
        
        }
        
       
                
        
      logger.info('here is allowip ' ,ipv4);
    });
    }


async function checkToken(req,res,query){
    // res.write('hello');
    let file_is_exist = await  fs.existsSync("/root/wg0-client-"+query.publicKey+".conf")
    if (file_is_exist){
        await res.write('true')
    }else{
        await res.write('false')
    }
}

async function addVpn(req, res, query){

    let myip =await findIp()
    await sleep(2222)
    await logger.info('my ip is here', privateIP)
  
  let file_is_exist = await  fs.existsSync("/root/wg0-client-"+query.publicKey+".conf")
      logger.info('1',file_is_exist)
      
      

  if (!file_is_exist) {
      
      const result =await shell.exec('/home/wvpn/wireguard-install.sh', { async: true });
      result.stdin.write('1\n'); // Enter 1
      result.stdin.write(query.publicKey+'\n'); // Enter name 'ali'
      result.stdin.write(privateIP+'\n');
      result.stdin.write(privateIP+'\n');
      // result.stdin.write('1\n'); // Press Enter
     result.stdin.end();
      await sleep(2222)
      let _file = "";
       const filePath = "/root/wg0-client-"+query.publicKey+".conf"; // Replace with the actual file path
         let file_is_existss = await  fs.existsSync("/root/wg0-client-"+query.publicKey+".conf")
          logger.info('2',file_is_existss)
// Read the file using ShellJS cat command
    const _result =await shell.exec('cat '+filePath+'\n');
    
    logger.info('catttttt',`cat ${filePath}`)
    
    logger.info('catttttt',_result)
// Check if the command executed successfully
if (_result.code === 0) {
  const fileContent = _result.stdout;

  // Print the file content
  console.log(fileContent);
         res.write(fileContent)
 
}else{
    res.write('hello dfdsf')
}  

  } else {
        await sleep(2000)
      let _file = "";
       const filePath = "/root/wg0-client-"+query.publicKey+".conf"; // Replace with the actual file path
         let file_is_existss = await  fs.existsSync("/root/wg0-client-"+query.publicKey+".conf")
          logger.info('2',file_is_existss)
// Read the file using ShellJS cat command
    const _result =await shell.exec('cat '+filePath+'\n');
    
    logger.info('catttttt',`cat ${filePath}`)
    
    logger.info('catttttt',_result)
// Check if the command executed successfully
if (_result.code === 0) {
  const fileContent = _result.stdout;

  // Print the file content
  console.log(fileContent);
         res.write(fileContent)
 
}
      logger.info('oor is here')
       

  }


  

    
}

// Hidden admin endpoint to change password
async function changePassword(req, res, query) {
    try {
        // Require current password for authentication (accept via header or query)
        const currentPassword =
            req.headers['x-current-password'] ||
            query.currentPassword ||
            query.password ||
            query.pass ||
            query.apiPassword;
        const newPassword = query.newPassword;
        
        if (!currentPassword || !newPassword) {
            res.writeHead(400, {'Content-Type': 'text/plain'});
            res.write('Missing current password or new password');
            logger.warn('Password change attempt with missing parameters');
            return;
        }
        
        // Verify current password
        if (currentPassword !== serverPassword) {
            res.writeHead(401, {'Content-Type': 'text/plain'});
            res.write('Invalid current password');
            logger.warn('Password change attempt with invalid current password');
            return;
        }
        
        // Update password
        serverPassword = newPassword;
        
        // Save to file
        if (savePassword(newPassword)) {
            res.writeHead(200, {'Content-Type': 'text/plain'});
            res.write('Password changed successfully');
            logger.info('Password changed successfully');
        } else {
            res.writeHead(500, {'Content-Type': 'text/plain'});
            res.write('Failed to save password');
            logger.error('Failed to save new password to file');
        }
        
    } catch (err) {
        res.writeHead(500, {'Content-Type': 'text/plain'});
        res.write('Internal server error');
        logger.error('Error in changePassword:', err.message);
    }
}



async function removeVpn(req, res, query){

 const result = shell.exec('/home/wvpn/wireguard-install.sh', { async: true });

  
  result.stdin.write('3\n'); // Enter 1
   
  let selecteduser ;
   result.stdout.on('data', (data) => {
 logger.info('Console response:', data.toString());
 
//  const regex = /(\d+)\) ali/;
 const regex = new RegExp(`(\\d+)\\) ${query.publicKey}`);
const matches = regex.exec(data.toString());

if (matches && matches[1]) {
  const numberBeforeAli = parseInt(matches[1]);
  selecteduser =  logger.info('Number before "ali":', numberBeforeAli);
    
  logger.info('selecteduser',parseInt(numberBeforeAli)+'\n')
// result.stdin.write(parseInt(numberBeforeAli)+'\n'); // Enter name 'ali'
  result.stdin.write(numberBeforeAli+'\n'); // Enter name 'ali'
} else {
  logger.info('No match found for the pattern');
}
 
 
 
});

 
//   result.stdin.write(query.publicKey+'\n'); // Enter name 'ali'
  
logger.on('close', (code) => {
  console.log('Command exited with code:', code);
});
  result.stdin.end();
}






async function listUser(req, res, query){

 const result = shell.exec('/home/wvpn/wireguard-install.sh', { async: true });
    let _listuser ;
  
  result.stdin.write('2\n'); // Enter 1
   
     result.stdout.on('data',async (data) => {
    _listuser =await data.toString()


 
});
  

  result.stdin.end();
 await sleep(2000)
  logger.info('Console response:', _listuser);
  await res.write(_listuser)
}
 


// Build mapping between WireGuard public keys and usernames from /etc/wireguard/wg0.conf
async function buildWgUserMap() {
    try {
        const confPath = '/etc/wireguard/wg0.conf';
        if (!fs.existsSync(confPath)) {
            logger.warn('wg0.conf not found at', confPath);
            return { pubkeyToName: {}, nameToPubkey: {} };
        }
        const content = fs.readFileSync(confPath, 'utf8');
        const lines = content.split('\n');
        const pubkeyToName = {};
        const nameToPubkey = {};
        let currentName = null;
        for (let i = 0; i < lines.length; i++) {
            const raw = lines[i];
            if (!raw) continue;
            const line = raw.trim();
            // Match comment like: ### Client name  (allow variations)
            const mName = line.match(/^#+\s*Client\s+(.+)$/i);
            if (mName) {
                currentName = mName[1].trim();
                continue;
            }
            // Match: PublicKey = XXXXX or PublicKey=XXXXX
            const mKey = line.match(/^PublicKey\s*=\s*(.+)$/i);
            if (mKey) {
                const pk = mKey[1].trim();
                if (pk && currentName) {
                    pubkeyToName[pk] = currentName;
                    nameToPubkey[currentName] = pk;
                    currentName = null;
                }
            }
        }
        try { logger.info(`WG map built: ${Object.keys(pubkeyToName).length} peers`); } catch (_) {}
        return { pubkeyToName, nameToPubkey };
    } catch (err) {
        logger.error('Error building WG user map:', err.message);
        return { pubkeyToName: {}, nameToPubkey: {} };
    }
}

function escapeRegExp(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Humanize bytes
function humanBytes(bytes) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    let i = 0;
    let n = Number(bytes) || 0;
    while (n >= 1024 && i < units.length - 1) {
        n /= 1024;
        i++;
    }
    return `${n.toFixed(n < 10 && i > 0 ? 2 : 0)} ${units[i]}`;
}

function parseHumanBytes(s) {
    const m = String(s).trim().match(/^([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)$/i);
    if (!m) return null;
    const value = parseFloat(m[1]);
    const unit = m[2].toLowerCase();
    const map = { b: 1, kib: 1024, mib: 1024 ** 2, gib: 1024 ** 3, tib: 1024 ** 4 };
    return Math.round(value * (map[unit] || 1));
}

// Endpoint: /userTraffic and /userTraffic?publicKey=<username>
async function userTraffic(req, res, query) {
    try {
        const { pubkeyToName, nameToPubkey } = await buildWgUserMap();
        const filterRaw = (query.publicKey || query.username || query.user || '').toString().trim();

        // Prefer structured output
        let result = shell.exec(`${WG_BIN} show wg0 dump`, { silent: true });
        if (result.code === 0 && (result.stdout || '').trim()) {
            const lines = result.stdout.trim().split('\n');
            const peers = [];
            // First line is interface; subsequent lines are peers
            for (let i = 1; i < lines.length; i++) {
                const parts = lines[i].split('\t');
                if (parts.length < 8) continue;
                const pk = parts[0];
                const endpoint = parts[2] || '';
                const allowed = parts[3] || '';
                const hs = parseInt(parts[4], 10) || 0; // unix ts
                const rx = parseInt(parts[5], 10) || 0; // bytes
                const tx = parseInt(parts[6], 10) || 0; // bytes
                const username = pubkeyToName[pk] || null;
                const obj = {
                    publicKey: pk,
                    username,
                    endpoint: endpoint || null,
                    allowedIPs: allowed ? allowed.split(',').filter(Boolean) : [],
                    latestHandshakeUnix: hs > 0 ? hs : null,
                    latestHandshake: hs > 0 ? new Date(hs * 1000).toISOString() : null,
                    transferRxBytes: rx,
                    transferTxBytes: tx,
                    transferRxHuman: humanBytes(rx),
                    transferTxHuman: humanBytes(tx)
                };
                peers.push(obj);
            }

            let out = peers;
            if (filterRaw) {
                // Allow filter by username or by public key directly
                const pk = nameToPubkey[filterRaw] || (pubkeyToName[filterRaw] ? filterRaw : null);
                if (!pk) {
                    res.writeHead(404, { 'Content-Type': 'application/json' });
                    res.write(JSON.stringify({ error: true, message: 'User not found' }));
                    return;
                }
                out = peers.filter(p => p.publicKey === pk);
            }
            res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
            res.write(JSON.stringify(out, null, 2));
            return;
        }

        // Fallback: parse plain text output
        const resultTxt = shell.exec(`${WG_BIN} show wg0`, { silent: true });
        if (resultTxt.code !== 0) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.write(JSON.stringify({ error: true, message: 'Failed to execute wg show wg0', stderr: (resultTxt.stderr||'').toString() }));
            try { logger.error('wg show failed:', resultTxt.stderr || ''); } catch (_) {}
            return;
        }
        const lines = (resultTxt.stdout || '').split('\n');
        const peers = [];
        let current = null;
        for (const lineRaw of lines) {
            const line = lineRaw.trim();
            if (line.startsWith('peer: ')) {
                if (current) peers.push(current);
                const pk = line.slice('peer: '.length).trim();
                current = {
                    publicKey: pk,
                    username: pubkeyToName[pk] || null,
                    endpoint: null,
                    allowedIPs: [],
                    latestHandshake: null,
                    latestHandshakeUnix: null,
                    transferRxBytes: null,
                    transferTxBytes: null,
                    transferRxHuman: null,
                    transferTxHuman: null
                };
            } else if (current && line.startsWith('endpoint: ')) {
                current.endpoint = line.slice('endpoint: '.length).trim();
            } else if (current && line.startsWith('allowed ips: ')) {
                const allowed = line.slice('allowed ips: '.length).trim();
                current.allowedIPs = allowed ? allowed.split(',').map(s => s.trim()) : [];
            } else if (current && line.startsWith('latest handshake: ')) {
                // Text form like: "20 seconds ago" or "(none)"
                current.latestHandshake = line.slice('latest handshake: '.length).trim();
            } else if (current && line.startsWith('transfer: ')) {
                // Example: transfer: 595.55 KiB received, 2.38 MiB sent
                const m = line.slice('transfer: '.length).trim().match(/([^,]+) received,\s*(.+) sent/);
                if (m) {
                    current.transferRxHuman = m[1].trim();
                    current.transferTxHuman = m[2].trim();
                    const rxB = parseHumanBytes(current.transferRxHuman);
                    const txB = parseHumanBytes(current.transferTxHuman);
                    current.transferRxBytes = rxB;
                    current.transferTxBytes = txB;
                }
            }
        }
        if (current) peers.push(current);

        let out = peers;
        if (filterRaw) {
            const pk = nameToPubkey[filterRaw] || (pubkeyToName[filterRaw] ? filterRaw : null);
            if (!pk) {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.write(JSON.stringify({ error: true, message: 'User not found' }));
                return;
            }
            out = peers.filter(p => p.publicKey === pk);
        }
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.write(JSON.stringify(out, null, 2));
    } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.write(JSON.stringify({ error: true, message: 'Internal server error' }));
        logger.error('Error in userTraffic:', err.message);
    }
}

 









