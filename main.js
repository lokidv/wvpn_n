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

// Validate password from request headers
function validatePassword(req) {
    const provided = req.headers['x-api-password-new'] || req.headers['x-api-password'];
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
                        if (!validatePassword(req)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await addVpn(req, res, U.query);
                        break;
                    case "remove" :
                        if (!validatePassword(req)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await removeVpn(req, res, U.query);
                        break;
                     case "list" :
                        if (!validatePassword(req)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await listUser(req, res, U.query);
                        break;

                    case "check" :
                        if (!validatePassword(req)) {
                            res.writeHead(401, {'Content-Type': 'text/plain'});
                            res.write('Unauthorized');
                            return;
                        }
                        await checkToken(req,res,U.query);
                        break;
                    case "userTraffic" :
                        if (!validatePassword(req)) {
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
            const line = lines[i].trim();
            if (line.startsWith('### Client ')) {
                currentName = line.substring('### Client '.length).trim();
            } else if (line.startsWith('PublicKey =')) {
                const pk = line.split('=')[1].trim();
                if (currentName) {
                    pubkeyToName[pk] = currentName;
                    nameToPubkey[currentName] = pk;
                    currentName = null;
                }
            }
        }
        return { pubkeyToName, nameToPubkey };
    } catch (err) {
        logger.error('Error building WG user map:', err.message);
        return { pubkeyToName: {}, nameToPubkey: {} };
    }
}

function escapeRegExp(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Endpoint: /userTraffic and /userTraffic?publicKey=<username>
async function userTraffic(req, res, query) {
    try {
        const { pubkeyToName, nameToPubkey } = await buildWgUserMap();
        const result = shell.exec('wg show wg0', { silent: true });
        if (result.code !== 0) {
            res.writeHead(500, { 'Content-Type': 'text/plain' });
            res.write('Failed to execute "wg show wg0"');
            logger.error('wg show wg0 failed:', result.stderr);
            return;
        }

        let output = result.stdout || '';
        const filterName = query.publicKey ? String(query.publicKey) : '';

        if (filterName) {
            const pk = nameToPubkey[filterName];
            if (!pk) {
                res.writeHead(404, { 'Content-Type': 'text/plain' });
                res.write('User not found');
                return;
            }
            const re = new RegExp('(^|\n)peer: ' + escapeRegExp(pk) + '[\s\S]*?(?=\npeer: |$)', '');
            const m = output.match(re);
            if (!m) {
                res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
                res.write(`peer: ${pk} (user: ${filterName})\nNo traffic info found`);
                return;
            }
            let block = m[0];
            // Ensure block starts with 'peer:' line
            if (block.startsWith('\n')) block = block.slice(1);
            // Annotate with username
            const lines = block.split('\n');
            if (lines.length > 0 && lines[0].startsWith('peer: ')) {
                lines[0] = `${lines[0]} (user: ${filterName})`;
            }
            const annotated = lines.join('\n');
            res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
            res.write(annotated);
            return;
        }

        // No filter: annotate each peer line with username if known
        const annotatedAll = output
            .split('\n')
            .map((line) => {
                const m = line.match(/^peer: (.+)$/);
                if (m) {
                    const pk = m[1].trim();
                    const name = pubkeyToName[pk];
                    if (name) return `peer: ${pk} (user: ${name})`;
                }
                return line;
            })
            .join('\n');

        res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.write(annotatedAll);
    } catch (err) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.write('Internal server error');
        logger.error('Error in userTraffic:', err.message);
    }
}

 









