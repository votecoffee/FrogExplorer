"""Authored leaf-frog adhesive discs and deforming interdigital skin. MIT.

These surfaces are generated from the original rig's digit landmarks. They
read no meshes, photographs or texture files.
"""
from math import sin, cos, pi

from mathutils import Vector


# Inner to outer on either foot. The fourth digit reaches farthest, and the
# shorter fifth digit wraps out to the side of the pad fan.
HIND_DIGIT_FAN = (
    (-.73, .0148),
    (-.34, .0218),
    (.082, .0273),
    (.49, .0303),
    (.96, .0225),
)


def hind_palm(frog, name, center, bone):
    """Shape the orange foot base from the narrow heel toward the toe roots."""
    vertices, faces, uv = [], [], []
    rings, segments = 14, 24
    for i in range(rings+1):
        phi = pi*i/rings
        for j in range(segments+1):
            theta = 2*pi*j/segments
            forward = -sin(phi)*sin(theta)
            across = sin(phi)*cos(theta)
            point = Vector((.00635*across*(1+.34*forward),
                            -.00725*forward,
                            .00024+.00144*cos(phi)*(1+.16*forward)))
            vertices.append(center+point)
            uv.append((j/segments, i/rings))
    for i in range(rings):
        for j in range(segments):
            a = i*(segments+1)+j
            b = a+segments+1
            faces.append((a, b, b+1, a+1))
    return frog.mesh(name, vertices, faces, uv, [{bone:1} for _ in vertices], frog.orange)


def adhesive_pad(frog, name, points, bone, size, hind=False):
    center = points[-1]+Vector((0, 0, .00010))
    direction = points[-1]-points[-2]
    forward = Vector((direction.x, direction.y, 0)).normalized()
    across = Vector((-forward.y, forward.x, 0))
    vertices = [];faces = [];uv = []
    rings, segments = 12, 28
    for i in range(rings+1):
        phi = pi*i/rings;r = sin(phi);vertical = cos(phi)
        if vertical>=0:z = (.00139 if hind else .0017)*vertical**.85
        else:
            t = min(1, -vertical/.65);z = -.00135*t*t*(3-2*t)
        for j in range(segments+1):
            angle = 2*pi*j/segments
            longitudinal = .0042*size*r*cos(angle)
            lateral = .0038*size*r*sin(angle)*(.96+.16*cos(angle))
            if hind:
                longitudinal += .00045*size*r
                lateral *= .98+.11*cos(angle)
            vertices.append(center+forward*longitudinal+across*lateral+Vector((0, 0, z)))
            uv.append((j/segments, i/rings))
    for i in range(rings):
        for j in range(segments):
            a = i*(segments+1)+j;b = a+segments+1
            faces.append((a, b, b+1, a+1))
    return frog.mesh(name, vertices, faces, uv, [{bone:1} for _ in vertices], frog.orange)


def digital_web(frog, side, label, digits):
    vertices = [];faces = [];uv = [];weights = []
    palm_bone = 'DEF-'+label+'.'+side
    columns, rows = 9, 5
    for gap, (left, right) in enumerate(zip(digits[:-1], digits[1:])):
        base = len(vertices)
        if label == 'foot':
            # Anchor to the first toe segments so the web follows their motion.
            reach = (.66, .74, .74, .68)[gap]
            a = left[0][0].lerp(left[0][1], reach)
            b = right[0][0].lerp(right[0][1], reach)
            scallop = (.33, .24, .24, .31)[gap]
        else:
            a = left[0][0].lerp(left[0][-1], .40)
            b = right[0][0].lerp(right[0][-1], .40)
            scallop = .34
        for layer in range(2):
            for row in range(rows):
                r = row/(rows-1)
                for column in range(columns):
                    t = column/(columns-1)
                    root = left[0][0].lerp(right[0][0], t)
                    edge = root+(a.lerp(b, t)-root)*(1-scallop*sin(pi*t))
                    point = root.lerp(edge, r)
                    point.z += .00030*sin(pi*r)*sin(pi*t)+(.00012 if layer==0 else -.00012)
                    vertices.append(point);uv.append((t, r))
                    palm = .75*(1-r)**2
                    weights.append({palm_bone:palm, left[1][0]:(1-palm)*(1-t), right[1][0]:(1-palm)*t})
        count = rows*columns
        for row in range(rows-1):
            for column in range(columns-1):
                a0 = base+row*columns+column;b0 = a0+columns
                face = (a0, b0, b0+1, a0+1)
                normal = (vertices[face[1]]-vertices[face[0]]).cross(vertices[face[2]]-vertices[face[0]])
                if normal.z<0:face = tuple(reversed(face))
                faces.append(face);faces.append(tuple(index+count for index in reversed(face)))
        boundary = ([base+i for i in range(columns)]
                    +[base+row*columns+columns-1 for row in range(1,rows)]
                    +[base+(rows-1)*columns+i for i in range(columns-2,-1,-1)]
                    +[base+row*columns for row in range(rows-2,0,-1)])
        for a0,b0 in zip(boundary,boundary[1:]+boundary[:1]):faces.append((a0,b0,b0+count,a0+count))
    return frog.mesh('Scalloped '+label+' webbing '+side, vertices, faces, uv, weights, frog.orange)
