{EventEmitter} = require 'events'
util = require 'util'
_ = require 'underscore'
async = require 'async'
deepClone = require 'clone'
concat = require 'concat-stream'
path = require 'path'
fs = require 'fs'
# Create connection

Message = (connection, options={}) ->
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

    # Flatten files
    # Some body parsers
    flattenFiles = (files) ->
      isFlat = true
      for fieldName, file of files
        # normalize casing across multiple body parsers
        file.fieldname = file.fieldName if file.fieldName
        # if this is not a file object, the file(s) is/are
        # nested in this object somehwere
        continue if !isFlat
        if !file.path && typeof file == 'object'
          isFlat = false
          # remove the current layer of nesting
          _.extend files, file
          # delete the current level of nesting
          delete files[fieldName]
        else if file.fieldname && !files[file.fieldname] && file.fieldname != fieldName
          files[file.fieldname] = file
          delete files[fieldName]

      if isFlat
        return files
      else
        return flattenFiles files

    info.files = flattenFiles info.files if info.files

    # Copy files included in the request in the fixture's directory
    # and cleanup the file data
    if typeof info.files == 'object'
      for fieldName of info.files
        localPath = info.files[fieldName].path
        absPath = path.resolve process.cwd(), localPath
        dest = path.resolve process.cwd(), @options.fixtureDir, path.basename absPath
        fileStream = fs.createReadStream absPath
        writeStream = fs.createWriteStream dest
        fileStream.pipe writeStream
        info.files[fieldName].path = dest
        # prune some uneeded data from the file object
        delete info.files[fieldName].ws if info.files[fieldName].ws
        delete info.files[fieldName].headers if info.files[fieldName].headers

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
