#!/usr/bin/env python3
"""
LED Position Visualizer - Load and visualize Flutter-generated LED positions

Usage:
    python visualize.py led_positions.json
    python visualize.py led_positions.json --confidence
    python visualize.py led_positions.json --save output.png
"""

import argparse
import json
import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D


def load_led_positions(json_file):
    """Load LED positions from Flutter-generated JSON"""
    with open(json_file, 'r') as f:
        data = json.load(f)
    
    positions = data['positions']
    metadata = {
        'total_leds': data['total_leds'],
        'tree_height': data['tree_height'],
        'num_cameras': data.get('num_cameras', 0),
        'num_observed': data.get('num_observed', 0),
        'num_predicted': data.get('num_predicted', 0),
    }
    
    return positions, metadata


def visualize_3d(positions, metadata, show_confidence=False, save_path=None):
    """Create 3D visualization of LED positions"""
    
    # Separate observed and predicted
    observed = [p for p in positions if not p['predicted']]
    predicted = [p for p in positions if p['predicted']]
    
    # Extract coordinates
    obs_x = [p['x'] for p in observed]
    obs_y = [p['y'] for p in observed]
    obs_z = [p['z'] for p in observed]
    obs_conf = [p['confidence'] for p in observed]
    
    pred_x = [p['x'] for p in predicted]
    pred_y = [p['y'] for p in predicted]
    pred_z = [p['z'] for p in predicted]
    
    # Create figure
    fig = plt.figure(figsize=(12, 10))
    ax = fig.add_subplot(111, projection='3d')
    
    # Plot observed LEDs
    if show_confidence:
        scatter = ax.scatter(obs_x, obs_y, obs_z, 
                           c=obs_conf, cmap='viridis',
                           s=50, alpha=0.8, label='Observed',
                           vmin=0, vmax=1)
        plt.colorbar(scatter, ax=ax, label='Confidence', shrink=0.5)
    else:
        ax.scatter(obs_x, obs_y, obs_z, 
                  c='blue', s=50, alpha=0.8, label='Observed')
    
    # Plot predicted LEDs
    if predicted:
        ax.scatter(pred_x, pred_y, pred_z,
                  c='red', s=30, alpha=0.5, label='Predicted')
    
    # Draw cone outline
    draw_cone_outline(ax, metadata['tree_height'])
    
    # Labels and formatting
    ax.set_xlabel('X (meters)')
    ax.set_ylabel('Y (meters)')
    ax.set_zlabel('Z (meters)')
    ax.set_title(f'LED Tree Map - {metadata["total_leds"]} LEDs\n'
                f'{metadata["num_observed"]} observed, '
                f'{metadata["num_predicted"]} predicted')
    
    ax.legend()
    ax.set_box_aspect([1,1,1])
    
    # Set equal aspect ratio
    max_range = metadata['tree_height'] / 2
    ax.set_xlim([-max_range, max_range])
    ax.set_ylim([-max_range, max_range])
    ax.set_zlim([0, metadata['tree_height']])
    
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=300, bbox_inches='tight')
        print(f"Saved visualization to {save_path}")
    else:
        plt.show()


def draw_cone_outline(ax, height, num_points=50):
    """Draw cone outline for reference"""
    # Estimate cone radii (will be slightly off but gives reference)
    base_radius = height * 0.25
    top_radius = height * 0.025
    
    # Generate cone outline
    theta = np.linspace(0, 2*np.pi, num_points)
    
    # Bottom circle
    x_bottom = base_radius * np.cos(theta)
    y_bottom = base_radius * np.sin(theta)
    z_bottom = np.zeros_like(theta)
    
    # Top circle
    x_top = top_radius * np.cos(theta)
    y_top = top_radius * np.sin(theta)
    z_top = np.full_like(theta, height)
    
    # Draw circles
    ax.plot(x_bottom, y_bottom, z_bottom, 'k--', alpha=0.3, linewidth=1)
    ax.plot(x_top, y_top, z_top, 'k--', alpha=0.3, linewidth=1)
    
    # Draw vertical lines
    for i in range(0, num_points, num_points // 8):
        ax.plot([x_bottom[i], x_top[i]], 
               [y_bottom[i], y_top[i]], 
               [z_bottom[i], z_top[i]], 
               'k--', alpha=0.2, linewidth=0.5)


def visualize_2d_projections(positions, metadata, save_path=None):
    """Create 2D projection views (top, side, front)"""
    
    # Extract coordinates
    x = [p['x'] for p in positions]
    y = [p['y'] for p in positions]
    z = [p['z'] for p in positions]
    observed = [not p['predicted'] for p in positions]
    
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    
    # Top view (X-Y)
    axes[0].scatter([x[i] for i in range(len(x)) if observed[i]], 
                   [y[i] for i in range(len(y)) if observed[i]], 
                   c='blue', s=30, alpha=0.6, label='Observed')
    axes[0].scatter([x[i] for i in range(len(x)) if not observed[i]], 
                   [y[i] for i in range(len(y)) if not observed[i]], 
                   c='red', s=20, alpha=0.4, label='Predicted')
    axes[0].set_xlabel('X (meters)')
    axes[0].set_ylabel('Y (meters)')
    axes[0].set_title('Top View (X-Y)')
    axes[0].axis('equal')
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)
    
    # Side view (X-Z)
    axes[1].scatter([x[i] for i in range(len(x)) if observed[i]], 
                   [z[i] for i in range(len(z)) if observed[i]], 
                   c='blue', s=30, alpha=0.6)
    axes[1].scatter([x[i] for i in range(len(x)) if not observed[i]], 
                   [z[i] for i in range(len(z)) if not observed[i]], 
                   c='red', s=20, alpha=0.4)
    axes[1].set_xlabel('X (meters)')
    axes[1].set_ylabel('Z (meters)')
    axes[1].set_title('Side View (X-Z)')
    axes[1].grid(True, alpha=0.3)
    
    # Front view (Y-Z)
    axes[2].scatter([y[i] for i in range(len(y)) if observed[i]], 
                   [z[i] for i in range(len(z)) if observed[i]], 
                   c='blue', s=30, alpha=0.6)
    axes[2].scatter([y[i] for i in range(len(y)) if not observed[i]], 
                   [z[i] for i in range(len(z)) if not observed[i]], 
                   c='red', s=20, alpha=0.4)
    axes[2].set_xlabel('Y (meters)')
    axes[2].set_ylabel('Z (meters)')
    axes[2].set_title('Front View (Y-Z)')
    axes[2].grid(True, alpha=0.3)
    
    plt.suptitle(f'LED Tree Projections - {metadata["total_leds"]} LEDs', 
                fontsize=14, fontweight='bold')
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=300, bbox_inches='tight')
        print(f"Saved projections to {save_path}")
    else:
        plt.show()


def print_statistics(positions, metadata):
    """Print statistics about the LED positions"""
    print("\n" + "="*60)
    print("LED POSITION STATISTICS")
    print("="*60)
    
    print(f"\nTotal LEDs: {metadata['total_leds']}")
    print(f"Tree Height: {metadata['tree_height']:.2f}m")
    
    if metadata.get('num_cameras'):
        print(f"Number of Cameras: {metadata['num_cameras']}")
    
    print(f"\nObserved (triangulated): {metadata['num_observed']} "
          f"({100*metadata['num_observed']/metadata['total_leds']:.1f}%)")
    print(f"Predicted (interpolated): {metadata['num_predicted']} "
          f"({100*metadata['num_predicted']/metadata['total_leds']:.1f}%)")
    
    # Confidence statistics
    observed = [p for p in positions if not p['predicted']]
    if observed:
        confidences = [p['confidence'] for p in observed]
        print(f"\nConfidence (observed LEDs):")
        print(f"  Mean: {np.mean(confidences):.3f}")
        print(f"  Min:  {np.min(confidences):.3f}")
        print(f"  Max:  {np.max(confidences):.3f}")
        print(f"  High confidence (>0.8): {sum(1 for c in confidences if c > 0.8)} "
              f"({100*sum(1 for c in confidences if c > 0.8)/len(confidences):.1f}%)")
    
    # Spatial statistics
    x = [p['x'] for p in positions]
    y = [p['y'] for p in positions]
    z = [p['z'] for p in positions]
    heights = [p['height'] for p in positions]
    
    print(f"\nSpatial Distribution:")
    print(f"  X range: [{min(x):.3f}, {max(x):.3f}]m")
    print(f"  Y range: [{min(y):.3f}, {max(y):.3f}]m")
    print(f"  Z range: [{min(z):.3f}, {max(z):.3f}]m")
    print(f"  Height range: [{min(heights):.3f}, {max(heights):.3f}] (normalized)")
    
    # Angular distribution
    angles = [p['angle'] for p in positions]
    print(f"  Angle range: [{min(angles):.1f}°, {max(angles):.1f}°]")
    
    print("="*60 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Visualize LED positions from Flutter-generated JSON"
    )
    parser.add_argument(
        'json_file',
        help='Path to led_positions.json'
    )
    parser.add_argument(
        '--confidence',
        action='store_true',
        help='Color LEDs by confidence (default: blue/red for observed/predicted)'
    )
    parser.add_argument(
        '--save',
        metavar='PATH',
        help='Save visualization to file instead of showing'
    )
    parser.add_argument(
        '--projections',
        action='store_true',
        help='Show 2D projection views instead of 3D'
    )
    parser.add_argument(
        '--stats',
        action='store_true',
        help='Print statistics only (no visualization)'
    )
    
    args = parser.parse_args()
    
    # Load data
    print(f"Loading {args.json_file}...")
    positions, metadata = load_led_positions(args.json_file)
    print(f"Loaded {len(positions)} LED positions")
    
    # Print statistics
    if args.stats or not (args.projections or args.save):
        print_statistics(positions, metadata)
    
    # Create visualization
    if not args.stats:
        if args.projections:
            visualize_2d_projections(positions, metadata, args.save)
        else:
            visualize_3d(positions, metadata, args.confidence, args.save)


if __name__ == '__main__':
    main()
