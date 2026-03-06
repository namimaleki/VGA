# VGA Shape Drawer on FPGA (SystemVerilog)

This is a small **hardware graphics engine** written in **SystemVerilog** that drives a **VGA framebuffer core** to draw shapes on a **160×120** pixel grid. The whole point of the project is building **datapaths + FSMs** that generate `(x, y, colour, plot)` signals correctly, one pixel per clock.

The main constraint that shapes everything here is simple:

> The framebuffer interface can only write **one pixel per clock cycle**, so every drawing operation becomes a **multi-cycle FSM-controlled algorithm**.

---

## What this project does

- Clears the screen by writing black to every pixel
- Draws vertical colour stripes across the screen
- Draws a circle boundary using the **Bresenham circle algorithm**
- Draws a **Reuleaux triangle boundary** by combining 3 circles and clipping out everything that doesn’t belong

---

## How the VGA pipeline works here

I didn’t generate VGA sync signals manually. The VGA core handles scanout and timing. My logic only drives these inputs:

- `x` in `[0..159]`
- `y` in `[0..119]`
- `colour` as 3-bit RGB
- `plot` as the “write enable” for the framebuffer  
  when `plot=1`, the core writes `(x,y)=colour` on the next rising edge

Because the physical board DAC uses **8-bit** colour while the VGA core internally uses **10-bit**, the top-level slices the output colour buses where needed.

---

## Overall architecture

Everything follows the same structure:

### 1) A top-level FSM that sequences the whole run
- clear screen after reset
- wait for user start
- clear again (so the result is deterministic)
- run the drawing module
- assert done and hold it until start is released

### 2) A clear-screen datapath
Clearing is just writing black to all pixels using counters:
- scan `y = 0..119`
- when `y` wraps, increment `x`
- total clear work = `160×120 = 19200` pixel writes

### 3) A VGA signal mux
Only one thing can drive `(VGA_X, VGA_Y, VGA_COLOUR, VGA_PLOT)` at a time:
- during clear states → the clear counters drive black pixels
- during draw states → the shape module drives pixels
- otherwise → `plot=0` so nothing accidentally gets overwritten

---

## Stripe fill (screen pattern)

### Goal
Fill the full screen with vertical stripes where the colour repeats every 8 columns.

### Strategy
- use a full-screen scan just like clear
- but set `colour = x[2:0]` so columns repeat `0..7`

---

## Circle drawing (Bresenham)

### Goal
Draw a circle boundary only (no fill) using integer-only math:
- centre `(centre_x, centre_y)`
- radius `r`
- colour

### Strategy
This uses the Bresenham circle algorithm:
- each loop iteration generates up to **8 symmetric pixels** (octants)
- then one update step adjusts the Bresenham decision variables
- repeat until the algorithm finishes

### Details that mattered
- **Input latching**  
  drawing takes many cycles, so I latch `centre_x`, `centre_y`, `radius`, `colour` at the start so nothing shifts mid-run
- **Bounds clipping**  
  if a candidate pixel is off-screen, I keep `plot=0` for that cycle  
  but I still advance the octant counter so timing stays clean and I never write invalid pixels

---

## Reuleaux triangle drawing

### Goal
Draw a Reuleaux triangle boundary (pointy end up) using:
- centre `(centre_x, centre_y)`
- diameter `D`
- colour

### Strategy
A Reuleaux triangle boundary can be seen as:
- 3 circles of radius `D`
- each circle centered at a corner of an equilateral triangle
- the final boundary is the part of each circle that lies **inside the other two circles**

So the approach is:
1. compute the 3 corner centres from `(centre_x, centre_y, D)`
2. run Bresenham circle generation for each corner centre
3. for each candidate boundary pixel:
   - check if it is inside the other two circles
   - only plot if it passes the rule

### The clipping rule
A candidate pixel from the “current” circle is kept only if:

- it is inside the screen bounds
- AND it satisfies both inside-circle checks:
  - `(px - o1x)^2 + (py - o1y)^2 <= D^2`
  - `(px - o2x)^2 + (py - o2y)^2 <= D^2`

This is what trims full circles down into the Reuleaux boundary arcs.

### Fixed point math
Corner placement needs `sqrt(3)` so I used a fixed-point approximation and integer division so the corner rounding stays consistent and synthesizable.

### Practical detail that mattered
Distance squared math needs **wide bit widths**. If the squared values overflow, the distances look incorrect and the inside checks stop working.

---

## Verification and testing

### RTL simulation
RTL testbenches focused on:
- handshake behavior  
  start held high until done  
  done stays high until start drops
- safety rules  
  if `plot=1` then `(x,y)` must always be within `[0..159]×[0..119]`
- sanity checks  
  make sure the draw phases actually produce plotted pixels and don’t get stuck

### Post-synthesis simulation
Post-synthesis tests treated the design as a black box:
- no internal signal peeking
- same safety and handshake checks through top-level I/O only

---

## Timing / cycle thinking

- **Full-screen pass** is always `160×120 = 19200` cycles
- Circle and Reuleaux are multi-cycle by nature because:
  - pixels are generated one per cycle
  - clipping still costs cycles even if a pixel isn’t written, because the algorithm still steps forward

---

## Tools used

- SystemVerilog
- Quartus Prime for synthesis / compilation
- ModelSim for simulation and debugging
- VGA framebuffer adapter core for scanout timing

