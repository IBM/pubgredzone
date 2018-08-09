#!/usr/bin/env node

// external dependencies
const express = require("express");
const request = require("request");
const Log = require("log");
const log = new Log("info");
const redis = require("redis");

// construct express app
const app = express();

// setup global list
let currentStream = {
  "stream_name": "foo",
  "alive": 100,
  "updated": (new Date()).toJSON(),
  "stream_url": "https://example.com",
};
let allStreams = [currentStream];
let client = redis.createClient({host: "redis-master"});
client.auth(process.env.REDIS_PASSWORD);

/**
 * Gets list of PUBG streams from Twitch API v5.
 * @callback {object} body - JSON object from Twitch API call. Contains list
 * of English language PUBG streams and their associated metadata.
 * @param {requestCallback} callback - The callback that handles the response.
 */
function listStreams(callback) {
  let clientID = process.env.clientID;
  let whitelist = process.env.ROTISSERIE_WHITELIST;
  let blacklist = process.env.ROTISSERIE_BLACKLIST;
  let gameURL = "https://api.twitch.tv/kraken/streams?game=PLAYERUNKNOWN'S+BATTLEGROUNDS&language=en&stream_type=live&limit=100";
  let options = {
    url: gameURL,
    headers: {
      "Client-ID": clientID,
    },
  };

  request(options, function(error, response, body) {
    if (body === undefined || body === null) {
      log.error("No response from Twitch.");
      if (error) {
        log.error("  " + error);
      }
      return Array([]);
    }
    if (error) log.error("error:", error);
    log.info("statusCode:", response.statusCode);

    bodyJSON = JSON.parse(body);
    allAgesStreams = bodyJSON.streams.filter(function(d) {
      return d.channel.mature === false;
    });
    if (whitelist !== null && whitelist !== undefined) {
      whitelist = whitelist.split(" ");
      allAgesStreams = allAgesStreams.filter(function(d) {
        return whitelist.includes(d.channel.name);
      });
    }
    if (blacklist !== null && blacklist !== undefined) {
      blacklist = blacklist.split(" ");
      allAgesStreams = allAgesStreams.filter(function(d) {
        return !blacklist.includes(d.channel.name);
      });
    }
    usernameList = allAgesStreams.map(function(d) {
      return d.channel["display_name"];
    });
    log.info(usernameList);
    return callback(usernameList);
  });
}

/**
 * Runner for listing streams and adding them to Redis
 */
function updateStreamsList() {
  // get list of twitch streams and record each one
  listStreams(function(response) {
    let streamsList = response;
    log.info(streamsList.length);

    client.sadd("stream-list", streamsList);
  });
}

/**
  Sets webpage to stream with lowest number of players alive, determined by
 * getLowestStream.
 * @param {object} stream - object containing name of string and number of
 * players alive.
 * @return {object} object - stream object containing stream metadata.
 */
function streamToObject(stream) {
  object = {};
  object["stream_name"] = stream.name;
  object["alive"] = stream.alive;
  object["stream_url"] = "https://player.twitch.tv/?channel=" + stream.name;
  object["updated"] = (new Date()).toJSON();
  return object;
}

/**
 * Finds lowest stream from list of streams and their associated playercounts
 * from redis.
 */
function findLowestStream() {
  // Grab first 50 elements of stream-by-alive. Because it's
  // a sorted set the elements will be returned by the number
  // of players alive, ascending.
  args = ["stream-by-alive", "0", "50", "WITHSCORES"];

  // Start a transaction to retrieve top 50 streams and then delete
  // the key.
  client.multi()
    .zrange(args)
    .del("stream-by-alive")
    .exec(function(err, responses) {
      if (err) throw err;

      // multi passes a list of repsonses for each command in the
      // transaction. We only care about the first one, the zrange
      // command.
      response = responses[0];

      newStreams = [];
      streams = [];

      // Turn list of stream,score items into a list of objects
      for (let idx = 0; idx < response.length; idx += 2) {
        obj = {"name": response[idx], "alive": response[idx+1]};
        streams.push(obj);
      }

      for (let stream of streams) {
        newStreams.push(streamToObject(stream));
      }

      if (newStreams.length > 0) {
        newStreams.reverse;
        allStreams = newStreams;
      } else {
        log.error("Empty stream list, not switching.");
      }
    });
}


/**
 * Runs logic to get lowest stream and starts express app server.
 */
function main() {
  // Pull list of streams every 20 seconds
  setInterval(function() {
    updateStreamsList();
  }, 20000);

  // Find the lowest stream every 30 seconds
  setInterval(function() {
    findLowestStream();
  }, 30000);

  // serve index.html
  app.get("/", function(req, res) {
    res.sendFile(__dirname + "/public/index.html");
  });

  // serve current leader stream object
  app.get("/current", function(req, res) {
    res.json(currentStream);
  });

  // serve all stream objects
  app.get("/all", function(req, res) {
    res.json(allStreams);
  });

  app.use(express.static("public"));

  // start http server and log success
  app.listen(3000, function() {
    log.info("Example app listening on port 3000!");
  });
}

main();
