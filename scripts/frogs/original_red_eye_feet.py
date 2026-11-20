"""Authored leaf-frog adhesive discs and deforming interdigital skin. MIT.

These surfaces are generated from the original rig's digit landmarks. They
read no meshes, photographs or texture files.
"""
from math import sin, cos, pi

from mathutils import Vector


FRONT_DIGIT_FAN = (
    (-.85, .0149),
    (-.27, .0219),
    (.24, .0240),
    (.79, .0192),
)

# Inner to outer on either foot. The fourth digit reaches farthest, and the
# shorter fifth digit wraps out to the side of the pad fan.
HIND_DIGIT_FAN = (
    (-.73, .0148),
    (-.34, .0218),
    (.082, .0273),
    (.49, .0303),
    (.96, .0225),
)


def digital_palm(frog, name, center, bone, hind):
    """Broaden the pad fan at the digit roots and taper it into the wrist."""
    width, length, thickness, flare = (
        (.00635, .00725, .00144, .34) if hind else (.00585, .00630, .00150, .25)
    )
    vertices, faces, uv = [], [], []
    rings, segments = 14, 24
    for i in range(rings+1):
        phi = pi*i/rings
        for j in range(segments+1):
            theta = 2*pi*j/segments
            forward = -sin(phi)*sin(theta)
            across = sin(phi)*cos(theta)
            point = Vector((width*across*(1+flare*forward),
                            -length*forward,
                            .00024+thickness*cos(phi)*(1+.16*forward)))
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
        if vertical>=0:z = (.00139 if hind else .00146)*vertical**.85
        else:
            t = min(1, -vertical/.65);z = -.00135*t*t*(3-2*t)
        for j in range(segments+1):
            angle = 2*pi*j/segments
            longitudinal = .0042*size*r*cos(angle)
            lateral = .0038*size*r*sin(angle)*(.96+.16*cos(angle))
            longitudinal += (.00045 if hind else .00027)*size*r
            if hind:
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
    reaches, scallops = (
        ((.66, .74, .74, .68), (.33, .24, .24, .31)) if label=='foot'
        else ((.64, .74, .68), (.39, .30, .36))
    )
    for gap, (left, right) in enumerate(zip(digits[:-1], digits[1:])):
        base = len(vertices)
        # Anchor to the proximal segments so the web follows the digit fan.
        a = left[0][0].lerp(left[0][1], reaches[gap])
        b = right[0][0].lerp(right[0][1], reaches[gap])
        scallop = scallops[gap]
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
