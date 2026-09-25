import Foundation

/// The sample pack written next to the packs README (same as docs/example-pack.json).
enum ExamplePack {
    static let json = #"""
{
  "id": "example",
  "name": "Example Pack",
  "description": "Shows every kind of thing a pack can add. Rename to example-pack.json to try it.",
  "palette": {
    "P": "#FF7EB6",
    "p": "#C94F86",
    "K": "#2B1B16",
    "W": "white",
    "G": "#3BA55C"
  },
  "art": {
    "cake": {
      "rows": [
        "...Y.Y...",
        "...K.K...",
        ".PPPPPPP.",
        ".PWPWPWP.",
        "PPPPPPPPP",
        "ppppppppp"
      ],
      "colors": {
        "Y": "yellow"
      }
    }
  },
  "accessories": {
    "party-glasses": {
      "title": "Party Glasses",
      "slot": "face",
      "rows": [
        ".PPPP..PPPP.",
        "PPKKPPPPKKPP",
        ".PPPP..PPPP."
      ]
    },
    "leaf": {
      "title": "Leaf Sprout",
      "slot": "head",
      "rows": [
        "GG.",
        ".GG",
        "..G",
        "..G"
      ],
      "offset": [
        2,
        0
      ]
    }
  },
  "clips": {
    "hop-hop": {
      "frames": [
        {
          "dy": 0,
          "squash": true
        },
        {
          "dy": 4,
          "arms": "up"
        },
        {
          "dy": 6,
          "arms": "up"
        },
        {
          "dy": 4,
          "arms": "up"
        },
        {
          "dy": 0,
          "squash": true
        }
      ],
      "frameTime": 0.08
    }
  },
  "activities": {
    "birthday": {
      "title": "Birthday Cake",
      "props": {
        "cake": {
          "art": "cake",
          "z": "front"
        }
      },
      "steps": [
        {
          "prop": "cake",
          "show": {
            "x": "star+20",
            "y": "floor"
          }
        },
        {
          "effect": "sparkle",
          "at": "cake"
        },
        {
          "face": "cake"
        },
        {
          "say": "Make a wish!",
          "time": 1.5
        },
        {
          "waitFor": [
            "click",
            "key:space"
          ],
          "timeout": 10,
          "else": [
            {
              "say": "I'll blow them out then!",
              "time": 1.5
            }
          ]
        },
        {
          "effect": "confetti",
          "at": "cake"
        },
        {
          "play": "hop-hop",
          "times": 3
        },
        {
          "prop": "cake",
          "hide": true
        }
      ]
    },
    "water": {
      "title": "Water Reminder",
      "menu": false,
      "steps": [
        {
          "wear": "leaf"
        },
        {
          "say": "Drink some water!",
          "time": 3
        },
        {
          "play": "hop-hop"
        },
        {
          "unwear": "leaf"
        }
      ]
    },
    "hello-app": {
      "title": "Hello, App",
      "menu": false,
      "steps": [
        {
          "face": "cursor"
        },
        {
          "play": "wave"
        }
      ]
    }
  },
  "bindings": [
    {
      "keys": "ctrl+opt+k",
      "run": "birthday"
    },
    {
      "sequence": "k",
      "run": "birthday"
    },
    {
      "sequence": "1 2 3",
      "say": "Counting is fun!"
    }
  ],
  "triggers": [
    {
      "every": "45m",
      "between": "09:00-18:00",
      "days": "weekdays",
      "run": "water"
    },
    {
      "at": "12:30",
      "say": "Lunch time!"
    },
    {
      "at": "17:00",
      "days": [
        "mon",
        "tue",
        "wed",
        "thu",
        "fri"
      ],
      "run": "stretch"
    },
    {
      "when": "app-open",
      "app": "Xcode",
      "run": "hello-app",
      "cooldown": "30m"
    },
    {
      "when": "app-quit",
      "app": "com.spotify.client",
      "say": "Aw, the music stopped."
    },
    {
      "when": "claude",
      "event": "Stop",
      "chance": 0.2,
      "run": "backflip"
    },
    {
      "when": "wake",
      "run": "stretch"
    }
  ]
}
"""#
}
