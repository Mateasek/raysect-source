
from raysect.optical import World, translate, rotate, Point3D, d65_white
from raysect.optical.observer import PinholeCamera
from raysect.optical.material.emitter import Checkerboard
from raysect.optical.material import Lambert
from raysect.optical.library import schott

from raysect.primitive import Box
from raysect.primitive.parabola import Parabola
from matplotlib.pyplot import *
import sys
sys.ps1 = 'SOMETHING'

# Import the new lens classes
from raysect.primitive.lens.spherical import *

rotation = 90.0

# Instantiate world object
world = World()

# Create lens objects
Parabola(radius=0.1, height=0.1, parent=world, material=schott("N-BK7"), transform=translate(0, 0, 0) * rotate(0, 0, 0))
# Parabola(radius=1000, height=0.1, parent=world, material=schott("N-BK7"), transform=translate(0, 0, 0) * rotate(0, 0, 0))
# Parabola(radius=0.1, height=0.1, parent=world, material=Lambert(), transform=translate(0, 0, 0) * rotate(0, 0, 0))

# Background Checkerboard
Box(Point3D(-50.0, -50.0, 0.1), Point3D(50.0, 50.0, 0.2), world, material=Checkerboard(0.01, d65_white, d65_white, 0.4, 0.8))

# Instantiate camera object, and configure its settings.
ion()
camera = PinholeCamera(fov=45, parent=world, transform=translate(0, 0, -0.25) * rotate(0, 0, 0))
camera.pixel_samples = 50
camera.spectral_rays = 5
camera.spectral_samples = 20
camera.pixels = (256, 256)
camera.display_progress = True

# Start ray tracing
camera.observe()

ioff()
camera.display()
show()
