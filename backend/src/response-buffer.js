'use strict';

class ResponseBuffer {
  constructor() {
    this.statusCode = 200;
    this.headers = {};
    this.headersSent = false;
    this.writableEnded = false;
    this.chunks = [];
  }

  setHeader(name, value) {
    if (this.headersSent) {
      throw new Error('Headers already sent');
    }

    this.headers[name.toLowerCase()] = value;
    return this;
  }

  getHeader(name) {
    return this.headers[name.toLowerCase()];
  }

  writeHead(status, headers = {}) {
    this.statusCode = status;

    for (const [name, value] of Object.entries(headers)) {
      this.setHeader(name, value);
    }

    this.headersSent = true;
    return this;
  }

  write(chunk) {
    if (this.writableEnded) {
      throw new Error('Response already ended');
    }

    this.headersSent = true;

    if (chunk !== undefined && chunk !== null) {
      this.chunks.push(
        Buffer.isBuffer(chunk)
          ? chunk
          : Buffer.from(String(chunk))
      );
    }

    return true;
  }

  end(chunk) {
    if (this.writableEnded) return this;

    if (chunk !== undefined && chunk !== null) {
      this.write(chunk);
    }

    this.headersSent = true;
    this.writableEnded = true;

    return this;
  }

  flush(res) {
    if (!this.writableEnded) {
      throw new Error('Response belum selesai');
    }

    res.writeHead(this.statusCode, this.headers);
    res.end(Buffer.concat(this.chunks));
  }
}

module.exports = { ResponseBuffer };