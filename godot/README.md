# PUA Godot migration

This directory is the new 3D implementation. The HTML/canvas build remains preserved as the design reference.

Acceptance rule: if a road, yard, light or transmitter makes the player think "I wonder what's over there?", they must be able to physically drive towards it.

First slice: Godot Mobile renderer, real 3D collision space, reversible free driving, chase camera, deterministic streamed world cells. No missions, scores, streaks or completion state. AI EYES remains identity-free.
