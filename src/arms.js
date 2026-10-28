// Trick Arms. Every weapon has two forms with their own movesets; turning
// it mid-combo is a trick attack that lands in the other form. In the full
// game each Arm's second form is also a key to the map (DESIGN.md, "Trick
// Arms"): the Lamplighter's Pole's Lantern form burns veils and lights the
// way.
//
// Attack timings are seconds. The hitbox runs from the player's front edge
// out to `reach`, and from `top` to `bottom` px relative to the feet
// (negative is up). lunge: forward speed on the first active frame, ground
// only. light: radius (px) of the light the form throws around you.
export const ARMS = {
  pole: {
    name: "Lamplighter's Pole",
    forms: {
      hook: {
        label: "Hook",
        light: 70,
        combo: [
          { damage: 14, reach: 44, top: -38, bottom: -8, startup: 0.07, active: 0.08, recovery: 0.17, lunge: 70 },
          { damage: 14, reach: 44, top: -38, bottom: -8, startup: 0.07, active: 0.08, recovery: 0.17, lunge: 70 },
          { damage: 22, reach: 52, top: -44, bottom: -4, startup: 0.11, active: 0.09, recovery: 0.26, lunge: 120 },
        ],
        trick: { damage: 28, reach: 74, top: -64, bottom: 0, startup: 0.1, active: 0.12, recovery: 0.28, lunge: 60, to: "lantern" },
      },
      lantern: {
        label: "Lantern",
        light: 150,
        burns: true,
        combo: [
          { damage: 26, reach: 78, top: -64, bottom: 4, startup: 0.16, active: 0.12, recovery: 0.3, lunge: 40 },
          { damage: 34, reach: 84, top: -70, bottom: 4, startup: 0.2, active: 0.12, recovery: 0.36, lunge: 50 },
        ],
        trick: { damage: 30, reach: 50, top: -44, bottom: -4, startup: 0.08, active: 0.09, recovery: 0.22, lunge: 140, to: "hook" },
      },
    },
  },
};

// Turning without attacking: a short beat where you can't strike.
export const TRANSFORM_TIME = 0.22;
