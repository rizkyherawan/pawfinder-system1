'use strict';
const { Readable } = require('node:stream');
const config = require('../src/config');
const { Router, corsHeaders } = require('../src/router');
const registerRoutes = require('../src/routes');
const { CloudSnapshot } = require('../src/cloud-snapshot');
const { ServerlessStore } = require('../src/serverless-store');
const { ResponseBuffer } = require('../src/response-buffer');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function sendJson(req,res,status,data) {
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',...corsHeaders(req)});
  res.end(JSON.stringify(data));
}
async function handler(req,res) {
  try {
    const url = new URL(req.url,'http://localhost');
    if(req.method === 'OPTIONS'){res.writeHead(204,corsHeaders(req));return res.end();}
    if(config.isProd && config.problems().length) return sendJson(req,res,503,{error:'Konfigurasi server belum siap'});
    if(url.pathname.startsWith('/api/') === false) return sendJson(req,res,404,{error:'Endpoint tidak ditemukan'});
    if(url.pathname.replace(/\/$/,'') === '/api/stream') return sendJson(req,res,501,{error:'Gunakan polling',code:'STREAM_DISABLED'});
    const chunks = [];
    let size = 0;
    if(['POST','PUT','PATCH'].includes(req.method)){
      for await(const chunk of req){
        const b = Buffer.from(chunk);
        size += b.length;
        if(size > 1300000) return sendJson(req,res,413,{error:'Payload terlalu besar'});
        chunks.push(b);
      }
    }
    const body = Buffer.concat(chunks);
    const cloud = new CloudSnapshot(process.env.PAWFINDER_CLOUD_ROOT || 'pawfinder_vercel_test');
    for(let attempt=0;attempt<8;attempt++){
      const session = await cloud.load();
      const store = new ServerlessStore(session);
      const router = new Router(store);
      registerRoutes(router);
      const replay = Readable.from(body.length ? [body] : []);
      replay.method = req.method;
      replay.url = req.url;
      replay.headers = req.headers;
      replay.socket = req.socket;
      const response = new ResponseBuffer();
      await router.handler(config.webDir)(replay,response);
      if(!response.writableEnded) throw new Error('Respons API belum selesai');
      try {
        if(response.statusCode < 500) await cloud.commit(session);
      } catch(error) {
        if(error.code === 'STATE_CONFLICT' && attempt < 7){
          await sleep(Math.min(800,100*Math.pow(2,attempt))*(0.5+Math.random()*0.5));
          continue;
        }
        throw error;
      }
      return response.flush(res);
    }
  } catch(error) {
    console.error('[serverless]',error.message);
    if(res.headersSent) return res.end();
    if(error.code === 'STATE_CONFLICT') return sendJson(req,res,409,{error:'Data sedang diperbarui. Silakan coba lagi.',code:'STATE_CONFLICT'});
    return sendJson(req,res,500,{error:'Terjadi kesalahan pada server'});
  }
};
let requestQueue = Promise.resolve();
module.exports = function queuedHandler(req,res) {
  const task = requestQueue.then(() => handler(req,res));
  requestQueue = task.catch(() => {});
  return task;
};
