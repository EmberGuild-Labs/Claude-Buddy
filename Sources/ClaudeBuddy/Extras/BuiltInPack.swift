import Foundation

/// The pack that ships with the app: tricks, a few accessories, and routines with props
/// (camping, fishing, the seesaw) that double as worked examples of the pack format.
/// Edit it like any pack; `--self-test` runs every activity in it.
enum BuiltInPack {
    static func load() -> Pack {
        PackParser.parse(data: Data(json.utf8), file: nil, fallbackID: "builtin")
    }

    static let json = #"""
{
  "id": "builtin",
  "name": "Built-in",
  "palette": {
    "D": "#6B4A2A",
    "T": "#E8A33D",
    "S": "#F2C46B",
    "K": "#2B1B16",
    "R": "#D63B3B",
    "r": "#A82A2A",
    "G": "#8A8F99",
    "W": "#8A5A2E",
    "w": "#5A3A1E",
    "O": "#FF8A1F",
    "Y": "#FFD447",
    "B": "#4A90D9",
    "b": "#7DB8F0",
    "L": "#BFE8FF",
    "N": "#5A3A1E",
    "E": "#2B1B16",
    "d": "#B65E42"
  },
  "art": {
    "tent": {
      "frames": {
        "closed": [
          ".............D.............",
          ".............D.............",
          "............DTD............",
          "...........DSTSD...........",
          "..........DTTTTTD..........",
          ".........DTTTTTTTD.........",
          "........DTTTTDTTTTD........",
          ".......DSTSTDDDTSTSD.......",
          "......DTTTTTDDDTTTTTD......",
          ".....DTTTTTDTDTDTTTTTD.....",
          "....DTTTTTTDTDTDTTTTTTD....",
          "....DTSTSTDTTDTTDTSTSTD....",
          "...DTTTTTTDTTDTTDTTTTTTD...",
          "..DTTTTTTDTTTDTTTDTTTTTTD..",
          ".DTTTTTTTDTTTDTTTDTTTTTTTD.",
          "DTSTSTSTDTTTTDTTTTDTSTSTSTD"
        ],
        "open": [
          ".............D.............",
          ".............D.............",
          "............DTD............",
          "...........DSTSD...........",
          "..........DTTTTTD..........",
          ".........DTTTTTTTD.........",
          "........DTTTTKTTTTD........",
          ".......DSTSTKKKTSTSD.......",
          "......DTTTTTKKKTTTTTD......",
          ".....DTTTTTKKKKKTTTTTD.....",
          "....DTTTTTTKKKKKTTTTTTD....",
          "....DTSTSTKKKKKKKTSTSTD....",
          "...DTTTTTTKKKKKKKTTTTTTD...",
          "..DTTTTTTKKKKKKKKKTTTTTTD..",
          ".DTTTTTTTKKKKKKKKKTTTTTTTD.",
          "DTSTSTSTKKKKKKKKKKKTSTSTSTD"
        ]
      },
      "frame": "closed"
    },
    "wagon": {
      "frames": {
        "logs": [
          "....................",
          "...wWWWWWWWWWw......",
          ".WWWWwWWWWwWWWWw....",
          ".wWWWWwWWWWwWWWW...K",
          "rrrrrrrrrrrrrrrrr..K",
          "RRRRRRRRRRRRRRRRR.K.",
          "RrrrrrrrrrrrrrrrRK..",
          "RRRRRRRRRRRRRRRRR...",
          "..KGK.......KGK.....",
          "..KKK.......KKK....."
        ],
        "empty": [
          "....................",
          "....................",
          "....................",
          "...................K",
          "rrrrrrrrrrrrrrrrr..K",
          "RRRRRRRRRRRRRRRRR.K.",
          "RrrrrrrrrrrrrrrrRK..",
          "RRRRRRRRRRRRRRRRR...",
          "..KGK.......KGK.....",
          "..KKK.......KKK....."
        ]
      },
      "frame": "logs"
    },
    "campfire": {
      "frames": {
        "a": [
          "..............",
          ".......O......",
          "......OO......",
          ".....OOO......",
          ".....OOOO.....",
          "....OOYYOO....",
          "....OOYYOO....",
          "...OOYYYYOO...",
          "...OOYYYYOO...",
          "...wwwwwwww...",
          "GWWWWWWWWWWWWG",
          "GwWWWWWWWWWWwG"
        ],
        "b": [
          "..............",
          ".....O........",
          "......O.......",
          "......OOO.....",
          "......OOO.....",
          ".....OOYOO....",
          "....OOYYOO....",
          "....OOYYYOO...",
          "...OOYYYYOO...",
          "...wwwwwwww...",
          "GWWWWWWWWWWWWG",
          "GwWWWWWWWWWWwG"
        ]
      },
      "frame": "a"
    },
    "pond": {
      "frames": {
        "a": [
          "....bbbbbbbbbbbbbbbbbbbbbbbb....",
          ".BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.",
          "BBBBBBLLBBBBLLBBBBLLBBBBLLBBBBBB",
          ".BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.",
          "....BBBBBBBBBBBBBBBBBBBBBBBB...."
        ],
        "b": [
          "....bbbbbbbbbbbbbbbbbbbbbbbb....",
          ".BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.",
          "BBBBBBBBLLBBBBLLBBBBLLBBBBLLBBBB",
          ".BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB.",
          "....BBBBBBBBBBBBBBBBBBBBBBBB...."
        ]
      },
      "frame": "a"
    },
    "fish": {
      "rows": [
        "..OOO...",
        ".OOOOO.O",
        "OKOOOOOO",
        ".OOOOO.O",
        "..OOO..."
      ]
    },
    "boot": {
      "rows": [
        "..NN..",
        "..NN..",
        "..NN..",
        "..NNNN",
        "NNNNNN",
        "NNNNNN"
      ]
    },
    "seesaw": {
      "frames": {
        "flat": [
          "............................................",
          "............................................",
          "...K....................................K...",
          "...K....................................K...",
          "wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
          "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
          ".....................GG.....................",
          "....................GGGG....................",
          "...................GGGGGG...................",
          "..................GGGGGGGG..................",
          ".................GGGGGGGGGG................."
        ],
        "left": [
          "........................................K...",
          "........................................wwww",
          ".................................wwwwwwwWWWW",
          "..........................wwwwwwwWWWWWWW....",
          "..................wwwwwwwwWWWWWWW...........",
          "...K.......wwwwwwwWWWWWWWW..................",
          "...KwwwwwwwWWWWWWW...GG.....................",
          "wwwwWWWWWWW.........GGGG....................",
          "WWWW...............GGGGGG...................",
          "..................GGGGGGGG..................",
          ".................GGGGGGGGGG................."
        ],
        "right": [
          "...K........................................",
          "wwww........................................",
          "WWWWwwwwwww.................................",
          "....WWWWWWWwwwwwww..........................",
          "...........WWWWWWWwwwwwwww..................",
          "..................WWWWWWWWwwwwwww.......K...",
          ".....................GG...WWWWWWWwwwwwwwK...",
          "....................GGGG.........WWWWWWWwwww",
          "...................GGGGGG...............WWWW",
          "..................GGGGGGGG..................",
          ".................GGGGGGGGGG................."
        ]
      },
      "frame": "flat"
    },
    "ball": {
      "rows": [
        "..BBBB..",
        ".BBBBBB.",
        "BBBEBBEB",
        "BBBEBBEB",
        "BBBBBBBB",
        "dBBBBBBd",
        ".dBBBBd.",
        "..dddd.."
      ],
      "colors": {
        "B": "body",
        "d": "bodyDark"
      }
    }
  },
  "accessories": {
    "wizard-hat": {
      "title": "Wizard Hat",
      "slot": "head",
      "colors": {
        "P": "#6B3FA0",
        "p": "#4A2A78",
        "Y": "gold"
      },
      "rows": [
        "......P.....",
        ".....PPP....",
        ".....PYP....",
        "....PPPPP...",
        "...PPPPPPP..",
        "..PPPPPPPPP.",
        "pppppppppppp"
      ]
    },
    "chef-hat": {
      "title": "Chef Hat",
      "slot": "head",
      "colors": {
        "C": "white",
        "c": "#E2DCCD"
      },
      "rows": [
        ".CC.CC.CC.",
        "CCCCCCCCCC",
        "CCCCCCCCCC",
        ".CCCCCCCC.",
        "..cccccc.."
      ]
    },
    "headphones": {
      "title": "Headphones",
      "slot": "head",
      "offset": [
        0,
        -4
      ],
      "colors": {
        "H": "#3C3F4A",
        "R": "red"
      },
      "rows": [
        "..HHHHHHHHHH..",
        ".H..........H.",
        ".H..........H.",
        "RR..........RR",
        "RR..........RR",
        "RR..........RR"
      ]
    },
    "sunglasses": {
      "title": "Sunglasses",
      "slot": "face",
      "colors": {
        "K": "#1E1E24",
        "g": "#6A7A8C"
      },
      "rows": [
        ".KKKK..KKKK.",
        ".KgKKKKKgKK.",
        "..KK....KK.."
      ]
    },
    "bowtie": {
      "title": "Bow Tie",
      "slot": "body",
      "offset": [
        0,
        1
      ],
      "colors": {
        "R": "red",
        "r": "#A82A2A"
      },
      "rows": [
        "R...R",
        "RRrRR",
        "R...R"
      ]
    },
    "cape": {
      "title": "Hero Cape",
      "slot": "back",
      "offset": [
        -7,
        -1
      ],
      "colors": {
        "R": "red",
        "r": "#A82A2A"
      },
      "rows": [
        "....RR",
        "...RRR",
        "..RRRR",
        ".RRRRR",
        ".RRRRr",
        "RRRRRr",
        "RRRRr.",
        "RRr..."
      ]
    },
    "fishing-rod": {
      "title": "Fishing Rod",
      "slot": "held",
      "colors": {
        "B": "#7A4B24",
        "W": "#D6D8DE",
        "R": "red"
      },
      "rows": [
        "......BW",
        ".....B.W",
        ".....B.W",
        "....B..W",
        "...B...R",
        "...B....",
        "..B.....",
        ".B......",
        ".B......",
        "B......."
      ]
    },
    "marshmallow": {
      "title": "Marshmallow Stick",
      "slot": "held",
      "colors": {
        "B": "#7A4B24",
        "M": "#F4F1EA"
      },
      "rows": [
        "......MM",
        "......MM",
        ".....B..",
        "....B...",
        "...B....",
        "..B.....",
        ".B......",
        "B......."
      ]
    }
  },
  "clips": {
    "backflip": {
      "tween": true,
      "frames": [
        {
          "squash": true,
          "time": 0.12
        },
        {
          "dy": 7,
          "angle": -90,
          "arms": "up",
          "eyes": "wide",
          "legs": "tucked",
          "time": 0.1
        },
        {
          "dy": 11,
          "angle": -180,
          "arms": "up",
          "eyes": "wide",
          "legs": "tucked",
          "time": 0.1
        },
        {
          "dy": 7,
          "angle": -270,
          "arms": "up",
          "eyes": "wide",
          "legs": "tucked",
          "time": 0.1
        },
        {
          "dy": 0,
          "angle": -360,
          "time": 0.06
        },
        {
          "squash": true,
          "angle": 0,
          "time": 0.1
        },
        {
          "pose": "cheer",
          "time": 0.4,
          "effect": "sparkle"
        }
      ]
    },
    "cartwheel": {
      "tween": true,
      "frames": [
        {
          "angle": 0,
          "arms": "up",
          "time": 0.12
        },
        {
          "angle": 90,
          "arms": "up",
          "dy": 3,
          "time": 0.12
        },
        {
          "angle": 180,
          "arms": "up",
          "dy": 4,
          "time": 0.12
        },
        {
          "angle": 270,
          "arms": "up",
          "dy": 3,
          "time": 0.12
        },
        {
          "angle": 360,
          "arms": "up",
          "time": 0.02
        },
        {
          "pose": "cheer",
          "angle": 0,
          "time": 0.35
        }
      ]
    },
    "bow": {
      "tween": true,
      "frames": [
        {
          "angle": 0,
          "time": 0.25
        },
        {
          "angle": 35,
          "eyes": "closed",
          "arms": "down",
          "time": 0.6
        },
        {
          "angle": 35,
          "eyes": "closed",
          "time": 0.05
        },
        {
          "angle": 0,
          "eyes": "happy",
          "time": 0.4
        }
      ]
    },
    "wave": {
      "frames": [
        {
          "arms": "waveHigh",
          "eyes": "happy"
        },
        {
          "arms": "waveLow",
          "eyes": "happy"
        },
        {
          "arms": "waveHigh",
          "eyes": "happy"
        },
        {
          "arms": "waveLow",
          "eyes": "happy"
        },
        {
          "arms": "waveHigh",
          "eyes": "happy"
        },
        {
          "arms": "waveLow",
          "eyes": "happy"
        },
        {
          "arms": "waveHigh",
          "eyes": "happy"
        },
        {
          "arms": "waveLow",
          "eyes": "happy"
        }
      ],
      "frameTime": 0.18
    },
    "robot": {
      "loop": true,
      "frameTime": 0.22,
      "frames": [
        {
          "arms": "up",
          "look": 1
        },
        {
          "arms": "holdOut",
          "bob": 1
        },
        {
          "arms": "down",
          "look": -1
        },
        {
          "arms": "typeA",
          "bob": 1
        },
        {
          "arms": "waveHigh",
          "eyes": "happy"
        },
        {
          "arms": "down",
          "bob": 1,
          "effect": "notes"
        }
      ]
    },
    "cast": {
      "frames": [
        {
          "arms": "hammerUp",
          "eyes": "wide",
          "time": 0.35
        },
        {
          "arms": "holdOut",
          "time": 0.25
        },
        {
          "arms": "holdOut",
          "eyes": "happy",
          "time": 0.4
        }
      ]
    },
    "reel": {
      "loop": true,
      "frameTime": 0.12,
      "frames": [
        {
          "arms": "typeA",
          "eyes": "wide"
        },
        {
          "arms": "typeB",
          "eyes": "wide"
        }
      ]
    },
    "stretch": {
      "tween": true,
      "frames": [
        {
          "arms": "up",
          "eyes": "closed",
          "dy": 0,
          "time": 0.6
        },
        {
          "arms": "up",
          "eyes": "closed",
          "dy": 2,
          "time": 0.8
        },
        {
          "arms": "up",
          "eyes": "closed",
          "dy": 2,
          "angle": 10,
          "time": 0.5
        },
        {
          "arms": "up",
          "eyes": "closed",
          "dy": 2,
          "angle": -10,
          "time": 0.6
        },
        {
          "arms": "down",
          "eyes": "happy",
          "dy": 0,
          "angle": 0,
          "time": 0.5
        }
      ]
    },
    "roll": {
      "loop": true,
      "tween": true,
      "frames": [
        {
          "art": "ball",
          "angle": 0,
          "time": 0.2
        },
        {
          "art": "ball",
          "angle": 90,
          "time": 0.2
        },
        {
          "art": "ball",
          "angle": 180,
          "time": 0.2
        },
        {
          "art": "ball",
          "angle": 270,
          "time": 0.2
        }
      ]
    },
    "handshake": {
      "frames": [
        {
          "arms": "holdOut",
          "time": 0.4
        },
        {
          "arms": "typeA",
          "time": 0.15
        },
        {
          "arms": "typeB",
          "time": 0.15
        },
        {
          "arms": "typeA",
          "time": 0.15
        },
        {
          "arms": "typeB",
          "time": 0.15
        },
        {
          "arms": "waveHigh",
          "eyes": "happy",
          "time": 0.3
        },
        {
          "arms": "up",
          "eyes": "happy",
          "dy": 3,
          "time": 0.2
        },
        {
          "pose": "cheer",
          "time": 0.3
        }
      ]
    },
    "munch": {
      "frames": [
        {
          "eyes": "happy",
          "bob": 1,
          "time": 0.2
        },
        {
          "eyes": "closed",
          "time": 0.2
        },
        {
          "eyes": "happy",
          "bob": 1,
          "time": 0.2
        },
        {
          "eyes": "closed",
          "time": 0.2
        },
        {
          "eyes": "happy",
          "bob": 1,
          "time": 0.2
        },
        {
          "eyes": "closed",
          "time": 0.2
        }
      ]
    }
  },
  "activities": {
    "backflip": {
      "title": "Backflip",
      "steps": [
        {
          "play": "backflip"
        }
      ]
    },
    "cartwheel": {
      "title": "Cartwheel",
      "steps": [
        {
          "play": "cartwheel"
        },
        {
          "play": "cartwheel"
        }
      ]
    },
    "bow": {
      "title": "Take a Bow",
      "steps": [
        {
          "face": "cursor"
        },
        {
          "play": "bow"
        },
        {
          "effect": "hearts",
          "count": 2
        }
      ]
    },
    "wave": {
      "title": "Wave",
      "endWith": "none",
      "steps": [
        {
          "face": "cursor"
        },
        {
          "play": "wave"
        }
      ]
    },
    "moonwalk": {
      "title": "Moonwalk",
      "steps": [
        {
          "face": "right"
        },
        {
          "walk": "here-50",
          "speed": 22,
          "backwards": true
        },
        {
          "play": "backflip"
        },
        {
          "face": "left"
        },
        {
          "walk": "here+50",
          "speed": 22,
          "backwards": true
        }
      ]
    },
    "robot-dance": {
      "title": "Robot Dance",
      "steps": [
        {
          "play": "robot"
        },
        {
          "wait": 4
        },
        {
          "stop": true
        },
        {
          "play": "backflip"
        }
      ]
    },
    "roll": {
      "title": "Roll Around",
      "steps": [
        {
          "walk": "here+60",
          "speed": 55,
          "clip": "roll"
        },
        {
          "walk": "here-60",
          "speed": 55,
          "clip": "roll"
        },
        {
          "effect": "stars",
          "count": 6
        },
        {
          "pose": "dizzy"
        },
        {
          "wait": 1
        }
      ]
    },
    "stretch": {
      "title": "Stretch Break",
      "steps": [
        {
          "say": "Stretch break!",
          "time": 1.5
        },
        {
          "play": "stretch"
        },
        {
          "play": "stretch"
        },
        {
          "say": "Ahh, much better.",
          "time": 1.6
        }
      ]
    },
    "fishing": {
      "title": "Go Fishing",
      "props": {
        "pond": {
          "art": "pond",
          "z": "back"
        },
        "fish": {
          "art": "fish",
          "z": "front"
        },
        "boot": {
          "art": "boot",
          "z": "front"
        }
      },
      "steps": [
        {
          "walk": "center-40",
          "speed": 40
        },
        {
          "face": "right"
        },
        {
          "prop": "pond",
          "show": {
            "x": "star+26",
            "y": "floor-3"
          }
        },
        {
          "effect": "sparkle",
          "at": "pond",
          "count": 5
        },
        {
          "wear": "fishing-rod"
        },
        {
          "play": "cast"
        },
        {
          "say": "Gone fishin'",
          "time": 1.5
        },
        {
          "pose": "sit"
        },
        {
          "loop": [
            {
              "prop": "pond",
              "frame": "a"
            },
            {
              "wait": 0.5
            },
            {
              "prop": "pond",
              "frame": "b"
            },
            {
              "wait": 0.5
            },
            {
              "if": "chance:0.08",
              "then": [
                {
                  "effect": "zzz",
                  "count": 1
                }
              ]
            }
          ],
          "until": [
            "click",
            "again"
          ],
          "for": 25
        },
        {
          "pose": "stand"
        },
        {
          "say": "A bite!",
          "time": 0.8
        },
        {
          "play": "reel"
        },
        {
          "wait": 1.2
        },
        {
          "stop": true
        },
        {
          "random": [
            [
              {
                "prop": "fish",
                "show": {
                  "x": "pond",
                  "y": "floor"
                }
              },
              {
                "prop": "fish",
                "move": {
                  "x": "star+12",
                  "y": "floor+16"
                },
                "time": 0.5,
                "ease": "out"
              },
              {
                "prop": "fish",
                "move": {
                  "y": "floor+10"
                },
                "time": 0.3
              },
              {
                "pose": "cheer"
              },
              {
                "effect": "hearts",
                "count": 3
              },
              {
                "say": "Got one!",
                "time": 1.4
              },
              {
                "prop": "fish",
                "move": {
                  "x": "pond",
                  "y": "floor-2"
                },
                "time": 0.5,
                "ease": "in"
              },
              {
                "prop": "fish",
                "hide": true
              },
              {
                "say": "Swim free, buddy.",
                "time": 1.4
              }
            ],
            [
              {
                "prop": "boot",
                "show": {
                  "x": "pond",
                  "y": "floor"
                }
              },
              {
                "prop": "boot",
                "move": {
                  "x": "star+12",
                  "y": "floor+14"
                },
                "time": 0.5,
                "ease": "out"
              },
              {
                "pose": "dizzy"
              },
              {
                "say": "...a boot?",
                "time": 1.6
              },
              {
                "prop": "boot",
                "move": {
                  "y": "floor-8"
                },
                "time": 0.4,
                "ease": "in"
              },
              {
                "prop": "boot",
                "hide": true
              }
            ]
          ]
        },
        {
          "pose": "stand"
        },
        {
          "unwear": "fishing-rod"
        },
        {
          "prop": "pond",
          "hide": true
        },
        {
          "effect": "sparkle",
          "count": 5
        }
      ]
    },
    "camping": {
      "title": "Go Camping",
      "props": {
        "tent": {
          "art": "tent",
          "z": "front"
        },
        "wagon": {
          "art": "wagon",
          "z": "back"
        },
        "fire": {
          "art": "campfire",
          "z": "back"
        }
      },
      "steps": [
        {
          "together": [
            [
              {
                "prop": "tent",
                "show": {
                  "x": "left+22",
                  "y": "floor-16"
                }
              },
              {
                "prop": "tent",
                "move": {
                  "y": "floor"
                },
                "time": 0.8,
                "ease": "out"
              }
            ],
            [
              {
                "walk": "left+22",
                "speed": 34
              }
            ]
          ]
        },
        {
          "prop": "tent",
          "frame": "open"
        },
        {
          "wait": 0.3
        },
        {
          "hide": true
        },
        {
          "prop": "tent",
          "shake": 0.9
        },
        {
          "wait": 1.1
        },
        {
          "prop": "wagon",
          "show": {
            "x": "tent",
            "y": "floor"
          }
        },
        {
          "prop": "wagon",
          "follow": "star",
          "side": "behind"
        },
        {
          "show": true
        },
        {
          "face": "right"
        },
        {
          "together": [
            [
              {
                "walk": "center+20",
                "speed": 26
              }
            ],
            [
              {
                "wait": 1.2
              },
              {
                "prop": "tent",
                "frame": "closed"
              },
              {
                "prop": "tent",
                "move": {
                  "y": "floor-16"
                },
                "time": 0.7,
                "ease": "in"
              },
              {
                "prop": "tent",
                "hide": true
              }
            ]
          ]
        },
        {
          "prop": "wagon",
          "follow": null
        },
        {
          "face": "left"
        },
        {
          "pose": "hold"
        },
        {
          "wait": 0.4
        },
        {
          "prop": "wagon",
          "frame": "empty"
        },
        {
          "face": "right"
        },
        {
          "pose": "stand"
        },
        {
          "prop": "fire",
          "show": {
            "x": "star+24",
            "y": "floor"
          }
        },
        {
          "effect": "stars",
          "at": "fire",
          "count": 6
        },
        {
          "pose": "sit"
        },
        {
          "wear": "marshmallow"
        },
        {
          "say": "Cozy.",
          "time": 1.2
        },
        {
          "loop": [
            {
              "prop": "fire",
              "frame": "a"
            },
            {
              "wait": 0.3
            },
            {
              "prop": "fire",
              "frame": "b"
            },
            {
              "wait": 0.3
            },
            {
              "if": "chance:0.1",
              "then": [
                {
                  "play": "munch"
                },
                {
                  "effect": "hearts",
                  "count": 1
                }
              ]
            },
            {
              "if": "night",
              "then": [
                {
                  "if": "chance:0.1",
                  "then": [
                    {
                      "effect": "zzz",
                      "count": 1
                    }
                  ]
                }
              ]
            }
          ],
          "until": [
            "click",
            "again"
          ],
          "for": 300
        },
        {
          "unwear": "marshmallow"
        },
        {
          "pose": "stand"
        },
        {
          "effect": "stars",
          "at": "fire",
          "count": 6
        },
        {
          "prop": "fire",
          "hide": true
        },
        {
          "walk": "wagon.left-10",
          "speed": 40
        },
        {
          "face": "right"
        },
        {
          "prop": "wagon",
          "follow": "star",
          "side": "ahead"
        },
        {
          "walk": "right-40",
          "speed": 40
        },
        {
          "prop": "wagon",
          "follow": null
        },
        {
          "prop": "wagon",
          "move": {
            "x": "offright+40"
          },
          "speed": 45,
          "ease": "linear"
        },
        {
          "prop": "wagon",
          "hide": true
        }
      ]
    },
    "seesaw": {
      "title": "Seesaw",
      "cast": [
        {
          "role": "star",
          "who": "main"
        },
        {
          "role": "friend",
          "who": "other"
        }
      ],
      "props": {
        "seesaw": {
          "art": "seesaw",
          "z": "back"
        }
      },
      "steps": [
        {
          "prop": "seesaw",
          "show": {
            "x": "center",
            "y": "floor"
          }
        },
        {
          "effect": "sparkle",
          "at": "seesaw",
          "count": 6
        },
        {
          "together": [
            {
              "who": "star",
              "steps": [
                {
                  "walk": "seesaw.left-6",
                  "speed": 45
                }
              ]
            },
            {
              "who": "friend",
              "steps": [
                {
                  "walk": "seesaw.right+6",
                  "speed": 45
                }
              ]
            }
          ]
        },
        {
          "together": [
            {
              "who": "star",
              "steps": [
                {
                  "hop": {
                    "x": "seesaw.left+4",
                    "y": "seesaw.bottom+7"
                  }
                },
                {
                  "face": "right"
                }
              ]
            },
            {
              "who": "friend",
              "steps": [
                {
                  "hop": {
                    "x": "seesaw.right-4",
                    "y": "seesaw.bottom+7"
                  }
                },
                {
                  "face": "left"
                }
              ]
            }
          ]
        },
        {
          "pose": "sit",
          "who": "star"
        },
        {
          "pose": "sit",
          "who": "friend"
        },
        {
          "ride": "seesaw",
          "who": "star",
          "offset": {
            "x": 4,
            "y": 7
          }
        },
        {
          "ride": "seesaw",
          "who": "friend",
          "offset": {
            "x": 40,
            "y": 7
          }
        },
        {
          "loop": [
            {
              "prop": "seesaw",
              "frame": "left"
            },
            {
              "ride": "seesaw",
              "who": "star",
              "offset": {
                "x": 4,
                "y": 4
              }
            },
            {
              "ride": "seesaw",
              "who": "friend",
              "offset": {
                "x": 40,
                "y": 10
              }
            },
            {
              "pose": {
                "legs": "tucked",
                "eyes": "happy",
                "arms": "up"
              },
              "who": "friend"
            },
            {
              "pose": "sit",
              "who": "star"
            },
            {
              "wait": 0.5
            },
            {
              "prop": "seesaw",
              "frame": "flat"
            },
            {
              "ride": "seesaw",
              "who": "star",
              "offset": {
                "x": 4,
                "y": 7
              }
            },
            {
              "ride": "seesaw",
              "who": "friend",
              "offset": {
                "x": 40,
                "y": 7
              }
            },
            {
              "wait": 0.12
            },
            {
              "prop": "seesaw",
              "frame": "right"
            },
            {
              "ride": "seesaw",
              "who": "star",
              "offset": {
                "x": 4,
                "y": 10
              }
            },
            {
              "ride": "seesaw",
              "who": "friend",
              "offset": {
                "x": 40,
                "y": 4
              }
            },
            {
              "pose": {
                "legs": "tucked",
                "eyes": "happy",
                "arms": "up"
              },
              "who": "star"
            },
            {
              "pose": "sit",
              "who": "friend"
            },
            {
              "wait": 0.5
            },
            {
              "prop": "seesaw",
              "frame": "flat"
            },
            {
              "ride": "seesaw",
              "who": "star",
              "offset": {
                "x": 4,
                "y": 7
              }
            },
            {
              "ride": "seesaw",
              "who": "friend",
              "offset": {
                "x": 40,
                "y": 7
              }
            },
            {
              "wait": 0.12
            }
          ],
          "times": 5
        },
        {
          "ride": null,
          "who": "star"
        },
        {
          "ride": null,
          "who": "friend"
        },
        {
          "pose": "stand",
          "who": "star"
        },
        {
          "pose": "stand",
          "who": "friend"
        },
        {
          "together": [
            {
              "who": "star",
              "steps": [
                {
                  "hop": {
                    "x": "seesaw.left-10",
                    "y": "floor"
                  }
                }
              ]
            },
            {
              "who": "friend",
              "steps": [
                {
                  "hop": {
                    "x": "seesaw.right+10",
                    "y": "floor"
                  }
                }
              ]
            }
          ]
        },
        {
          "effect": "stars",
          "at": "seesaw",
          "count": 6
        },
        {
          "prop": "seesaw",
          "hide": true
        },
        {
          "effect": "confetti",
          "who": "star"
        }
      ]
    },
    "handshake": {
      "title": "Secret Handshake",
      "cast": [
        {
          "role": "star",
          "who": "main"
        },
        {
          "role": "friend",
          "who": "other",
          "ifMissing": "unavailable"
        }
      ],
      "steps": [
        {
          "walk": "star+22",
          "who": "friend",
          "speed": 50
        },
        {
          "face": "friend",
          "who": "star"
        },
        {
          "face": "star",
          "who": "friend"
        },
        {
          "together": [
            {
              "who": "star",
              "steps": [
                {
                  "play": "handshake"
                }
              ]
            },
            {
              "who": "friend",
              "steps": [
                {
                  "play": "handshake"
                }
              ]
            }
          ]
        },
        {
          "together": [
            {
              "who": "star",
              "steps": [
                {
                  "play": "backflip"
                }
              ]
            },
            {
              "who": "friend",
              "steps": [
                {
                  "wait": 0.15
                },
                {
                  "play": "backflip"
                }
              ]
            }
          ]
        },
        {
          "effect": "hearts",
          "who": "star",
          "count": 2
        },
        {
          "effect": "hearts",
          "who": "friend",
          "count": 2
        }
      ]
    },
    "puppet": {
      "title": "Take the Controls",
      "steps": [
        {
          "say": "You drive!",
          "time": 1
        },
        {
          "pose": "stand"
        },
        {
          "puppet": {
            "speed": 45,
            "jump": 20,
            "hint": "Arrows move, Esc stops",
            "keys": {
              "f": [
                {
                  "play": "backflip"
                }
              ],
              "w": [
                {
                  "play": "wave"
                }
              ],
              "h": [
                {
                  "effect": "hearts",
                  "count": 3
                }
              ],
              "c": [
                {
                  "play": "cartwheel"
                }
              ],
              "b": [
                {
                  "play": "bow"
                }
              ]
            }
          }
        },
        {
          "say": "That was fun!",
          "time": 1.4
        }
      ]
    }
  },
  "bindings": [
    {
      "sequence": "up up down down",
      "run": "backflip"
    },
    {
      "sequence": "f",
      "run": "fishing"
    },
    {
      "sequence": "t",
      "run": "camping"
    },
    {
      "sequence": "s",
      "run": "seesaw"
    },
    {
      "sequence": "h",
      "run": "handshake"
    },
    {
      "sequence": "p",
      "run": "puppet"
    },
    {
      "sequence": "b",
      "run": "bow"
    },
    {
      "sequence": "w",
      "run": "wave"
    },
    {
      "sequence": "c",
      "run": "cartwheel"
    },
    {
      "sequence": "m",
      "run": "moonwalk"
    },
    {
      "sequence": "d",
      "run": "robot-dance"
    },
    {
      "sequence": "r",
      "run": "roll"
    },
    {
      "sequence": "x",
      "run": "stretch"
    }
  ]
}
"""#
}
