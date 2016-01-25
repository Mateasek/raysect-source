# cython: language_level=3

# Copyright (c) 2016, Dr Alex Meakins, Raysect Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     1. Redistributions of source code must retain the above copyright notice,
#        this list of conditions and the following disclaimer.
#
#     2. Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#
#     3. Neither the name of the Raysect Project nor the names of its
#        contributors may be used to endorse or promote products derived from
#        this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

from .camera import Camera
from raysect.core import translate
from raysect.optical.observer.point_generator import Rectangle, SinglePoint
from raysect.optical.observer.vector_generators import HemisphereCosine


# TODO: fix the numerous bits of broken functionality!
class CCD(Camera):
    # """ A camera observing an orthogonal (orthographic) projection of the scene, avoiding perspective effects.
    #
    # :param pixels: tuple containing the number of pixels along horizontal and vertical axis
    # :param width: width of the area to observe in meters, the height is deduced from the 'pixels' attribute
    # :param spectral_samples: number of spectral samples by ray
    # :param rays: number of rays. The total spectrum will be divided over all the rays. The number of rays must be >1 for
    #  dispersive effects.
    # :param parent: the scenegraph node which will be the parent of this observer.
    # :param transform: AffineMatrix describing the relative position/rotation of this node to the parent.
    # :param name: a printable name.
    # """

    def __init__(self, pixels=(720, 480), width=0.036, sensitivity=1.0, spectral_samples=21, spectral_rays=1,
                 pixel_samples=100, sub_sample=True, process_count=0, parent=None, transform=None, name=None):

        super().__init__(pixels=pixels, sensitivity=sensitivity, spectral_samples=spectral_samples,
                         spectral_rays=spectral_rays, pixel_samples=pixel_samples, process_count=process_count,
                         parent=parent, transform=transform, name=name)

        self.sub_sample = sub_sample
        self.width = width

        self._update_image_geometry()

        # todo: respect subsample setting
        self._point_generator = Rectangle(self.image_delta, self.image_delta)
        self._vector_generator = HemisphereCosine()

    def _update_image_geometry(self):

        self.image_delta = self._width / self._pixels[0]
        self.image_start_x = 0.5 * self._pixels[0] * self.image_delta
        self.image_start_y = 0.5 * self._pixels[1] * self.image_delta

    @property
    def pixels(self):
        return self._pixels

    @pixels.setter
    def pixels(self, pixels):
        # call base class pixels setter
        self.__class__.__base__.pixels.fset(self, pixels)
        self._update_image_geometry()

    @property
    def width(self):
        return self._width

    @width.setter
    def width(self, width):
        if width <= 0:
            raise ValueError("width can not be less than or equal to 0 meters.")
        self._width = width
        self._update_image_geometry()

    def _generate_pixel_transform(self, i, j):

        pixel_x = self.image_start_x - self.image_delta * i
        pixel_y = self.image_start_y - self.image_delta * j
        return translate(pixel_x, pixel_y, 0)