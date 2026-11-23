// Re-lock an updated family tree into FamilyTree.html using only the public key stored in that file.
// No password needed. Usage: node tools/publish-tree.mjs <tree-body.html> [FamilyTree.html]
// Never commit the unlocked tree body to this repository.
import fs from 'fs';import {webcrypto as crypto} from 'crypto';
const [bodyPath,sitePath='FamilyTree.html']=process.argv.slice(2);
if(!bodyPath){console.error('usage: node tools/publish-tree.mjs <tree-body.html> [FamilyTree.html]');process.exit(1)}
const site=fs.readFileSync(sitePath,'utf8');
const pubB64=site.match(/const PUB="([^"]+)"/)?.[1];
if(!pubB64){console.error('No public key in '+sitePath+'. Run the one-time setup first.');process.exit(1)}
const b64=u=>Buffer.from(u).toString('base64');
const pub=await crypto.subtle.importKey('spki',Buffer.from(pubB64,'base64'),{name:'RSA-OAEP',hash:'SHA-256'},false,['encrypt']);
const ck=await crypto.subtle.generateKey({name:'AES-GCM',length:256},true,['encrypt']);
const iv=crypto.getRandomValues(new Uint8Array(12));
const DATA={k:b64(await crypto.subtle.encrypt({name:'RSA-OAEP'},pub,await crypto.subtle.exportKey('raw',ck))),i:b64(iv),
  c:b64(await crypto.subtle.encrypt({name:'AES-GCM',iv},ck,new TextEncoder().encode(fs.readFileSync(bodyPath,'utf8'))))};
const out=site.replace(/const DATA=\{.*?\};/,()=>'const DATA='+JSON.stringify(DATA)+';');
if(out===site){console.error('Could not find the DATA line in '+sitePath);process.exit(1)}
fs.writeFileSync(sitePath,out);console.log('Updated '+sitePath);
