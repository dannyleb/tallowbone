# Browser benchmark

CPU-drawn (no GPU on the CI machine): compare rows, not absolute speed.

## Firefox, 1280x720

```
BENCHMARK  Mozilla/5.0 (X11; Linux x86_64; rv:158.0) Gecko/20100101 Firefox/158.0 / dpr 1
Mozilla / llvmpipe, or similar, gl_compatibility   window (1280, 720)   view (640.0, 360.0)   world drawn at 1280x720 (2.0x)
title screen: 285.4 ms, steady after 41.7 s (shaders compiling behind it)
first visits: street worst 1573 ms (5 hitches), canal worst 259 ms (5 hitches), undercroft worst 4958 ms (5 hitches)

config                             avg ms      fps    worst   script  physics
everything on                       284.3        4      325    265.0      5.5
no shadows                          273.3        4      310    260.4      5.6   saves 11.0 ms
no fog                              279.9        4      325    260.3      7.8   saves 4.4 ms
no reflections                      266.2        4      306    245.3      5.9   saves 18.1 ms
no bounce                           287.9        3      324    266.6      6.6   saves -3.6 ms
no glow                             272.1        4      314    251.2      6.3   saves 12.2 ms
no rain                             284.1        4      324    260.6      6.7   saves 0.2 ms
no far city                         284.4        4      323    263.2      6.7   saves -0.1 ms
no city                             240.4        4      343    219.8      6.8   saves 43.9 ms
no foreground                       289.3        3      345    270.9      8.5   saves -5.0 ms
no clutter                          291.8        3      329    266.8      7.2   saves -7.5 ms
no water light                      285.6        4      326    267.6      5.3   saves -1.3 ms
no plane                            280.9        4      318    255.2      6.1   saves 3.4 ms
no fx                               289.1        3      326    266.7      5.4   saves -4.8 ms
no hud                              286.7        3      334    267.7      5.6   saves -2.4 ms
no everything                       169.9        6      309    158.0      5.7   saves 114.4 ms
drawn at 1.5x (960x540)             187.4        5      212    169.9      5.4   saves 96.9 ms
drawn at 1.0x (640x360)             118.6        8      144    100.4      6.5   saves 165.7 ms
```

## Chrome, 1280x720

```
BENCHMARK  Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36 / dpr 1
WebKit / WebKit WebGL, gl_compatibility   window (1279, 663)   view (694.0, 360.0)   world drawn at 1279x663 (1.8x)
title screen: 255.8 ms, steady after 41.9 s (shaders compiling behind it)
first visits: street worst 1614 ms (5 hitches), canal worst 266 ms (5 hitches), undercroft worst 5234 ms (4 hitches)

config                             avg ms      fps    worst   script  physics
everything on                       277.5        4      314    258.3      7.1
no shadows                          260.8        4      297    241.3      7.1   saves 16.6 ms
no fog                              285.7        4      324    254.1      6.7   saves -8.2 ms
no reflections                      258.1        4      299    238.5      7.1   saves 19.3 ms
no bounce                           275.3        4      312    257.2      6.3   saves 2.1 ms
no glow                             262.4        4      298    240.3      9.7   saves 15.0 ms
no rain                             270.3        4      307    255.1      6.5   saves 7.2 ms
no far city                         272.1        4      314    252.3      6.6   saves 5.4 ms
no city                             223.7        4      298    206.4      7.1   saves 53.7 ms
no foreground                       274.4        4      314    255.6      6.9   saves 3.1 ms
no clutter                          276.1        4      310    258.6      6.7   saves 1.3 ms
no water light                      278.1        4      348    258.6      6.2   saves -0.6 ms
no plane                            266.9        4      321    247.0      6.8   saves 10.6 ms
no fx                               275.2        4      309    255.8      6.0   saves 2.2 ms
no hud                              279.1        4      311    267.1     11.7   saves -1.6 ms
no everything                       158.2        6      231    143.7      8.0   saves 119.2 ms
drawn at 1.5x (1041x540)            204.4        5      244    185.8      7.1   saves 73.0 ms
drawn at 1.0x (694x360)             126.9        8      176    119.0      7.4   saves 150.6 ms
```

## Firefox, 1280x720 at 2x (2560x1440 pixels, like a Retina screen)

```
BENCHMARK  Mozilla/5.0 (X11; Linux x86_64; rv:158.0) Gecko/20100101 Firefox/158.0 / dpr 2
Mozilla / llvmpipe, or similar, gl_compatibility   window (2560, 1440)   view (640.0, 360.0)   world drawn at 1920x1080 (3.0x)
title screen: 721.0 ms, steady after 23.9 s (shaders compiling behind it)
first visits: street worst 743 ms (5 hitches), canal worst 566 ms (5 hitches), undercroft worst 2001 ms (5 hitches)

config                             avg ms      fps    worst   script  physics
everything on                       582.3        2      657    543.7      5.8
drawn at 2.0x (1280x720)            323.9        3      384    284.7      6.2   saves 258.4 ms
drawn at 1.5x (960x540)             225.1        4      247    186.7      7.8   saves 357.2 ms
drawn at 1.0x (640x360)             157.5        6      179    121.5      7.8   saves 424.9 ms
```

## Desktop renderer (Forward+ on Vulkan, CPU-drawn), 1280x720

```
BENCHMARK  Linux
Unknown / llvmpipe (LLVM 20.1.2, 256 bits), forward_plus   window (1280, 720)   view (640.0, 360.0)   world drawn at 1280x720 (2.0x)
title screen: 10684.6 ms, steady after 68.5 s (shaders compiling behind it)
first visits: street worst 1863 ms (5 hitches), canal worst 1336 ms (4 hitches), undercroft worst 2780 ms (2 hitches)

config                             avg ms      fps    worst   script  physics
everything on                      1149.5        1     1234   1134.8      6.4
no shadows                         1595.5        1     2238   1579.4      7.0   saves -446.0 ms
no fog                             1118.4        1     1212   1103.4      6.6   saves 31.1 ms
no reflections                     1034.8        1     1111   1020.4      6.5   saves 114.7 ms
no bounce                          1093.8        1     1174   1080.0      5.8   saves 55.6 ms
no glow                            1087.8        1     1174   1074.2      6.0   saves 61.7 ms
no rain                            1121.1        1     1210   1106.3      6.6   saves 28.4 ms
no far city                        1017.0        1     1105   1003.3      5.8   saves 132.5 ms
no city                             804.6        1      956    790.3      6.2   saves 344.9 ms
no foreground                      1147.9        1     1229   1133.5      6.4   saves 1.6 ms
no clutter                         1143.5        1     1221   1129.6      6.1   saves 6.0 ms
no water light                     1147.3        1     1226   1133.2      6.2   saves 2.2 ms
no plane                           1067.2        1     1164   1053.3      5.8   saves 82.3 ms
no fx                              1170.1        1     1565   1155.4      6.4   saves -20.6 ms
no hud                             1180.8        1     1239   1166.9      6.2   saves -31.3 ms
no everything                       327.2        3      429    314.9      6.7   saves 822.3 ms
drawn at 1.5x (960x540)             760.8        1      802    746.2      6.8   saves 388.7 ms
drawn at 1.0x (640x360)             433.8        2      472    422.6      6.7   saves 715.7 ms
```
