import requests

application_id = ""
guild_id = ""
bot_token = ""

url = f"https://discord.com/api/v8/applications/{application_id}/guilds/{guild_id}/commands"

commands = [{
  "name":
  "parts",
  "type":
  1,
  "description":
  "List parts needed in a song.",
  "options": [{
    "name": "song",
    "description": "Title of the song's pad",
    "type": 3,
    "required": True
  }]
}, {
  "name":
  "songpart",
  "type":
  1,
  "description":
  "Get sheet for a song's part.",
  "options": [{
    "name": "song",
    "description": "Title of the song's pad",
    "type": 3,
    "required": True
  }, {
    "name": "part",
    "description": "Name of the part",
    "type": 3,
    "required": True
  }]
}, {
  "name":
  "needs",
  "type":
  1,
  "description":
  "Get songs in need of recording for a part.",
  "options": [{
    "name": "part",
    "description": "Name of an part or instrument.",
    "type": 3,
    "required": False
  }, {
    "name": "user",
    "description": "A user.",
    "type": 6,
    "required": False
  }, {
    "name": "role",
    "description": "A role.",
    "type": 8,
    "required": False
  }]
}, {
  "name":
  "songinfo",
  "type":
  1,
  "description":
  "Get info on a song.",
  "options": [{
    "name": "song",
    "description": "Title of the song's pad",
    "type": 3,
    "required": True
  }]
}]
# For authorization, you can use either your bot token
headers = {"Authorization": f"Bot {bot_token}"}

for json in commands:
  print(requests.post(url, headers=headers, json=json).json())
