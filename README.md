# Collision Damage
![Farming Simulator 25](https://img.shields.io/badge/Farming%20Simulator-25-4C8C2B)
[![ModHub](https://img.shields.io/badge/ModHub-Download-7CB342)](https://www.farming-simulator.com/mod.php?mod_id=361963&title=fs2025) [![Version](https://img.shields.io/badge/Version-1.2.0.0-blue)](https://github.com/)

Collision Damage adds additional vehicle damage after stronger collisions in Farming Simulator 25.

The mod uses the existing GIANTS vehicle damage system. It does not add visible deformation, but the normal damage value of the affected vehicle increases and can be repaired as usual.

## Features
- Additional vehicle damage after stronger impacts
- Sensor-based collision detection
- Support for vehicles, trailers and usable implements
- Improved detection of collisions involving front loaders, buckets and other attached equipment
- Optional damage for both vehicles involved in a collision
- Adjustable damage amount in the in-game settings
- Multiplayer support
- Server-side damage calculation

## How It Works

A strong loss of speed alone is not enough to cause damage.

The mod checks whether an actual collision occurred in the vehicle's travel or sensor area. This helps distinguish real impacts from normal braking, steering or vehicle movement.

When two usable vehicles, trailers or implements collide, both can receive additional damage if they support the standard GIANTS damage system.

Static objects such as buildings, trees and map decorations are not damaged.

The vehicle combination's own attached implements and trailers are not treated as separate crash participants.

## Damage Settings

The amount of additional collision damage can be adjusted in the in-game settings.

- 100% represents the default damage effect
- Lower values reduce the additional damage
- Higher values increase the additional damage

## Installation

### ModHub

Download and install the mod directly from the official ModHub.

### Manual Installation
Download FS25_CollisionDamage.zip.
Do not extract the ZIP file.

Copy it to:

Documents/My Games/FarmingSimulator2025/mods

## Important Notes
The mod does not add visible vehicle deformation.
Damage is applied through the standard GIANTS damage system.
Buildings, trees and other static obstacles do not receive damage.
Very weak contacts and normal driving situations should not cause damage.
Modded vehicles must support the standard vehicle damage system to receive collision damage.
