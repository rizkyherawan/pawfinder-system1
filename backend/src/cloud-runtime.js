'use strict';

function restoreRuntime(raw = {}) {
  raw = raw || {};

  return {
    live: new Map(Object.entries(raw.live || {})),
    commands: new Map(Object.entries(raw.commands || {})),
    discovered: new Map(Object.entries(raw.discovered || {})),
    usb: null,
  };
}

function serializeRuntime(runtime) {
  return {
    live: Object.fromEntries(runtime.live),
    commands: Object.fromEntries(runtime.commands),
    discovered: Object.fromEntries(runtime.discovered),
  };
}

module.exports = {
  restoreRuntime,
  serializeRuntime,
};