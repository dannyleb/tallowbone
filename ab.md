Desktop renderer, one machine (Model name:                              AMD EPYC 9V74 80-Core Processor); average frame (ms) over the benchmark's spots.

| config | cc84c22 | d413ea6 | d413ea6 vs cc84c22 |
|---|---|---|---|
| everything on | 913.0 | 832.3 | -9% |
| no shadows | 936.7 | 745.8 | -20% |
| no fog | 806.9 | 801.7 | -1% |
| no reflections | 741.4 | 738.8 | -0% |
| no bounce | 788.1 | 789.1 | +0% |
| no glow | 798.2 | 788.7 | -1% |
| no rain | 811.7 | 811.0 | -0% |
| no far city | 756.7 | 745.8 | -1% |
| no city | 615.6 | 599.5 | -3% |
| no foreground | 831.6 | 832.8 | +0% |
| no clutter | 827.1 | 843.0 | +2% |
| no water light | 829.3 | 852.3 | +3% |
| no plane | 771.3 | 783.6 | +2% |
| no fx | 833.9 | 850.5 | +2% |
| no hud | 829.9 | 842.1 | +1% |
| no everything | 229.6 | 242.5 | +6% |
| drawn at 1.5x (960x540) | 538.8 | 548.2 | +2% |
| drawn at 1.0x (640x360) | 322.6 | 323.6 | +0% |

cc84c22: title steady after 64.7 s; first visits, worst frame: street 1884 ms, canal 827 ms, undercroft 865 ms
d413ea6: title steady after 24.9 s; first visits, worst frame: street 908 ms, canal 894 ms, undercroft 1010 ms
