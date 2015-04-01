{EventEmitter} = require 'events'
util = require 'util'
_ = require 'underscore'
async = require 'async'
deepClone = require 'clone'
concat = require 'concat-stream'
path = require 'path'
fs = require 'fs'
# Create connection

Message = (connection, options) ->
  # Inherit from event emitter
  that = this
  EventEmitter.call this
  # Save the connection
  @connection = connection
  # Save the options
  @options = options
  # If there is a body already, don't buffer
  if connection.body
    that.body = connection.body
    async.setImmediate ->
      that.emit 'loaded'
      return
    return
  # Buffer the content of the connecftion
  connection.pipe concat((buff) ->
    # Save the body and emit a `loaded` event
    # DEV: The delay is so `async.waterfall` still operates when we enter it
    that.body = if buff.length then buff else ''
    async.setImmediate ->
      that.emit 'loaded'
      return
    return
  )
  return

util.inherits Message, EventEmitter
_.extend Message.prototype,
  pickMessageInfo: ->
    # DEV: Refer to http://nodejs.org/api/http.html#http_http_incomingmessage
    info = {}
    # DEV: This is an antipattern where we lose our stack trace
    [
      'httpVersion'
      'headers'
      'trailers'
      'method'
      'url'
      'statusCode'
      'files'
    ].forEach(((key) ->
      info[key] = deepClone(@connection[key])
      return
    ), this)

    # Copy files included in the request in the fixture's directory
    if typeof info.files == 'object'
      for fieldName of info.files
        localPath = info.files[fieldName].path
        absPath = path.resolve process.cwd(), localPath
        dest = path.resolve process.cwd(), @options.fixtureDir, info.files[fieldName].name
        fileStream = fs.createReadStream absPath
        writeStream = fs.createWriteStream dest
        fileStream.pipe writeStream
        info.files[fieldName].path = dest

    return info
  getRequestInfo: ->
    info = @pickMessageInfo()
    delete info.statusCode
    info.body = @body
    info
  getResponseInfo: ->
    info = @pickMessageInfo()
    delete info.url
    delete info.method
    info.body = @body
    info
module.exports = Message
