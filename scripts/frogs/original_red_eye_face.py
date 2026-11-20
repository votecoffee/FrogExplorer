"""Authored leaf-frog facial proportions and small anatomical surfaces. MIT.

Photographs guide proportions only. No image, mesh or animation is read here.
"""
from math import acos, sin, cos, exp, pi, sqrt

import numpy as np
from mathutils import Quaternion, Vector

EYE_RADIUS = .0085
EYE_ASPECT = (1.025, 1.00, .78)
EYE_APERTURE = 1.31
BODY_Y_RANGE = (-.083,.073)
NARIS_XY = (.0140,-.0740)
FACE_SECTIONS = [
    [-.083,.0064,.0444,.0492],[-.078,.0153,.0445,.0541],
    [-.069,.0231,.0450,.0572],[-.049,.0325,.0459,.0628],
    [-.030,.0306,.0405,.0612]]


def eye_frame(sign):
    normal = Vector((sign*.72,-.695,.10)).normalized()
    horizontal = normal.cross(Vector((0,0,1))).normalized()
    return normal,horizontal,horizontal.cross(normal).normalized()


def lid_axis(sign):
    normal = eye_frame(sign)[0]
    return (Vector((0,0,1))*.18-normal).normalized()


def lid_sweep(sign, amount):
    normal = eye_frame(sign)[0]
    hinge = Vector((0,0,1)).cross(normal).normalized()
    return Quaternion(hinge, acos(lid_axis(sign).dot(normal))*amount)


def shorten_muzzle(point):
    """Give the nose a rounded overhang above the fitted lower lip."""
    point = Vector(point)
    if point.y<-.061:
        front = min(1,max(0,(point.y+.083)/.0105));front = front*front*(3-2*front)
        t = min(1,max(0,(point.y+.083)/.022));t = t*t*(3-2*t)
        point.y += .0072*(1-t)
        tip = 1-front
        squared_width = (point.x/.0095)**2
        side = squared_width/(.30+squared_width)
        bridge = exp(-((point.z-.0500)/.0038)**2)
        point.y += tip*(.00145*side-.00068*(1-.40*side)*bridge)
        point.x *= 1-.18*(1-t)+.17*tip
    return point


def orbital_recess(point,centers):
    """Recess the iris opening and roll the surrounding cheek into the socket."""
    point=Vector(point)
    for sign,center in centers:
        normal,horizontal,vertical=eye_frame(sign);delta=point-center
        radius=EYE_RADIUS*sin(EYE_APERTURE)
        across = delta.dot(horizontal)/(EYE_ASPECT[0]*radius)
        height = delta.dot(vertical)/(EYE_ASPECT[1]*radius)
        rho = sqrt(across*across+height*height)
        if rho >= 1.86:
            continue
        depth = delta.dot(normal)
        blend = min(1, max(0, (1.18-rho)/.18))
        point -= normal*max(0, depth-.0010)*blend**2*(3-2*blend)
        # The upper arc widens toward the forehead. Below the eye the cheek
        # rolls out more gently, leaving the lid margin thinner.
        angle_radius = max(1.02,rho)
        upper = max(0,height)/angle_radius
        lower = max(0,-height)/angle_radius
        toward_nose = max(0,sign*across)/angle_radius
        span = .57+.24*upper+.03*toward_nose
        margin = min(1,max(0,(rho-1.02)/span))
        relief = (.00044+.0026*upper**1.4+.00105*lower)*(1+.18*toward_nose)
        falloff = sin(pi*margin)**2*exp(-((depth+.001)/.007)**2)
        point += falloff*(normal*relief+vertical*(.0032*upper**1.6))
    return point


def add_orbital_socket(frog, side, center, normal, horizontal, vertical):
    """Seat a thinner upper socket and fuller lower rim behind the cornea."""
    rings, segments = 24, 48
    radius = EYE_RADIUS+.0003
    vertices, faces, uv = [], [], []
    for i in range(rings+1):
        t = i/rings
        phi = (pi-1.25)*t
        blend = sin(pi*t)**2
        depth = -radius*cos(phi)*EYE_ASPECT[2]-.00155*blend
        for j in range(segments+1):
            angle = 2*pi*j/segments
            height = sin(angle)
            upper, lower = max(0,height), max(0,-height)
            spread = 1+blend*(.087*lower-.056*upper)
            lip = (.00012*lower-.00028*upper)*t**6
            radial = (-horizontal*(cos(angle)*EYE_ASPECT[0])
                      +vertical*(height*EYE_ASPECT[1]))
            vertices.append(center+normal*(depth+lip)+radial*(radius*sin(phi)*spread))
            uv.append((j/segments,t))
    for i in range(rings):
        for j in range(segments):
            a = i*(segments+1)+j
            b = a+segments+1
            faces.append((a,a+1,b+1,b))
    frog.mesh('Green orbital socket '+side, vertices, faces, uv,
              [{'Head':1} for _ in vertices], frog.orbit_mat)


def add_upper_eyelid(frog, side, sign, center, normal, horizontal, vertical):
    """Sculpt the arched fold with the lid shut, then turn it into its rest pose."""
    radius = EYE_RADIUS+.0005
    edge = sin(1.36)
    to_rest = lid_sweep(sign, 1).inverted()
    rows = np.concatenate((np.linspace(-1,-.18,10),
                           (-.12,-.08,-.04,0,.035,.07,.12),
                           np.linspace(.18,1,12)))
    segments = 48
    stride = segments+1
    vertices, faces, uv = [], [], []
    for row in rows:
        for column in range(stride):
            lateral = 2*column/segments-1
            y = row+.19*(1-row*row)*(1-lateral*lateral)
            x = lateral*sqrt(max(0,1-y*y))
            squared_radius = x*x+y*y
            depth = radius*EYE_ASPECT[2]*sqrt(max(0,1-edge*edge*squared_radius))
            # Lower the crown. Fade the crease and raised upper edge into the corners.
            depth -= .00040*max(0,1-squared_radius)
            crease = -.00026*exp(-(row/.054)**2)
            ridge = .00023*exp(-((row-.065)/.055)**2)
            depth += (1-lateral**4)*(crease+ridge)
            radial = horizontal*(x*EYE_ASPECT[0])+vertical*(y*EYE_ASPECT[1])
            vertices.append(center+to_rest@(normal*depth+radial*(radius*edge)))
            uv.append((.5+.5*x,.5+.5*y))
    for row in range(len(rows)-1):
        for column in range(segments):
            a = row*stride+column
            b = a+stride
            faces.append((a,b,b+1,a+1))
    frog.mesh('Mobile upper eyelid '+side,vertices,faces,uv,
              [{'Lid.'+side:1} for _ in vertices], frog.orbit_mat)


def add_mouth_corner(frog, side, sign, eye_center):
    """Shape a soft rear lip with its upper and lower edges seated in skin."""
    rows = np.concatenate((np.linspace(0,.144,7),np.linspace(.17,1,19)))
    length_steps, height_steps = len(rows)-1, 9
    stride = height_steps+1
    inner_offset = length_steps*stride
    vertices, uv, weights, faces = [], [], [], []
    for layer in range(2):
        # Both surfaces share the row at the rolled front edge.
        for along in rows[layer:]:
            y = -.0418+.0150*along
            arch = sin(pi*along)
            width = frog.section_at(y)[1]
            upper_angle = .13+.065*arch
            x = sign*width*cos(upper_angle)
            upper = orbital_recess((x,y,frog.body_height(x,y,True)),[(sign,eye_center)])
            x = sign*frog.jaw_width(y)*cos(.18)
            roundness = min(1,along/.145)
            layer_blend = .5+(layer-.5)*sqrt(roundness*(2-roundness))
            edge_inset = .00070+.00043*(1-arch)+.00058*layer_blend
            lower = Vector((x,y,frog.body_height(x-sign*edge_inset,y,False)-.00023))
            for j in range(stride):
                t = j/height_steps
                rise = sin(pi*t)
                curved = rise*arch
                front = rise**1.45*(1-along)
                roll = .00112*rise*exp(-((along-.13)/.13)**2)
                point = upper.lerp(lower,t)
                point.x += sign*(.00130*curved+roll-edge_inset-.0028*front)
                point.y += .00065*curved+.0092*front
                vertices.append(point)
                theta = upper_angle*(1-t)+.022*t
                uv.append(((point.y-BODY_Y_RANGE[0])/(BODY_Y_RANGE[1]-BODY_Y_RANGE[0]),
                           theta/(2*pi) if sign>0 else .5-theta/(2*pi)))
                jaw = t*t*(3-2*t)
                trunk = min(1,max(0,(y+.038)/.023))
                spine = (1-jaw)*trunk*trunk*(3-2*trunk)
                weights.append({'FX-jaw':jaw,'DEF-spine.003':spine,'Head':1-jaw-spine})
    for i in range(length_steps):
        for j in range(height_steps):
            a = i*stride+j
            b = a+stride
            faces.append((a,b,b+1,a+1))
    outer_count = len(faces)
    def inner(index):
        return index if index < stride else index+inner_offset

    for face in faces[:outer_count]:
        faces.append(tuple(inner(index) for index in reversed(face)))
    perimeter = ([i*stride for i in range(length_steps+1)]
                 +[length_steps*stride+j for j in range(1,stride)]
                 +[i*stride+height_steps for i in range(length_steps-1,-1,-1)]
                 +list(range(height_steps-1,0,-1)))
    for a,b in zip(perimeter,perimeter[1:]+perimeter[:1]):
        wall = tuple(dict.fromkeys((a,inner(a),inner(b),b)))
        if len(wall) >= 3:
            faces.append(wall)
    corner = frog.mesh('Soft mouth corner '+side,vertices,faces,uv,weights,frog.body_mat)
    corner.data.materials.append(frog.oral_dark)
    for face in corner.data.polygons[outer_count:2*outer_count]:
        face.material_index = 1


def add_features(frog):
    for side,sign in [('L',-1),('R',1)]:
        center = frog.bones['FX_eye.'+side][0];n,u,v = eye_frame(sign)
        add_orbital_socket(frog, side, center, n, u, v)
        frog.cap('Red corneal surface '+side,center,n,EYE_RADIUS,EYE_APERTURE,
                 frog.iris,'FX_eye.'+side,24,64,aspect=EYE_ASPECT)
        add_upper_eyelid(frog, side, sign, center, n, u, v)
        ring, rim_widths = [], []
        for angle in np.linspace(0,2*pi,81):
            height = sin(angle)
            upper, lower = max(0,height), max(0,-height)
            radius = EYE_RADIUS+.00028+.00014*upper+.00018*lower
            depth = radius*cos(EYE_APERTURE)*EYE_ASPECT[2]-.00022*lower
            radial = u*(cos(angle)*EYE_ASPECT[0])+v*(height*EYE_ASPECT[1])
            ring.append(center+n*depth+radial*(radius*sin(EYE_APERTURE)))
            rim_widths.append(.000052+.000083*upper**1.5+.000015*lower)
        frog.tube('Fine eye rim '+side,ring,rim_widths,['Head']*(len(ring)-1),frog.rim_mat,1,8)
        lip = []
        for y in np.linspace(-.0827,-.0315,48):
            x = sign*frog.jaw_width(y)
            lip.append((x,y,frog.body_height(x,y,False)-.00005))
        lip_radii = [.000048+.000060*sin(pi*i/(len(lip)-1)) for i in range(len(lip))]
        frog.tube('Mouth commissure '+side,lip,lip_radii,['Head']*(len(lip)-1),frog.dark,1,8)
        add_mouth_corner(frog,side,sign,center)
        # The dark aperture and soft inner rim sit in the sculpted skin dimple.
        x,y = sign*NARIS_XY[0],NARIS_XY[1];z = frog.body_height(x,y)
        delta = .0001
        gx = (frog.body_height(x+delta,y)-frog.body_height(x-delta,y))/(2*delta)
        gy = (frog.body_height(x,y+delta)-frog.body_height(x,y-delta))/(2*delta)
        normal = Vector((-gx,-gy,1)).normalized()
        rotation = Vector((0,0,1)).rotation_difference(normal).to_matrix()
        center_naris = Vector((x,y,z))+normal*.00021
        frog.ellipsoid('Nostril '+side,center_naris,(.00062,.00042,.00007),frog.dark,'Head',10,24,rotation)
        rim = []
        for a in np.linspace(0,2*pi,33):
            rim_x = x+.00078*cos(a)
            rim_y = y+.00070*sin(a)
            rim_z = frog.body_height(rim_x,rim_y)+.00007
            rim.append((rim_x,rim_y,rim_z))
        frog.tube('Soft naris rim '+side,rim,[.000075]*len(rim),['Head']*(len(rim)-1),frog.fold_mat,1,8)
        def cheek_surface(y, theta):
            width = frog.section_at(y)[1]
            x = sign*width*cos(theta)
            p = (x,y,frog.body_height(x,y,theta>=0))
            return orbital_recess(p, [(sign,center)])

        def trunk_skin(point):
            t=min(1,max(0,(point.y+.038)/.023));head=1-t*t*(3-2*t)
            return {'Head':head,'DEF-spine.003':1-head}

        # The membrane follows the cheek at its edge and rises gently at its
        # center, with the same texture coordinates as the underlying skin.
        vertices=[];uv=[];faces=[]
        for i in range(13):
            for j in range(49):
                a=2*pi*j/48;r=i/12
                y = -.0362+.0037*r*cos(a)
                theta = .38+.31*r*sin(a)
                point = cheek_surface(y, theta)
                point.x += sign*(.00008+.00060*(1-r*r)**2)
                vertices.append(point)
                uv.append(((y-BODY_Y_RANGE[0])/(BODY_Y_RANGE[1]-BODY_Y_RANGE[0]),theta/(2*pi) if sign>0 else .5-theta/(2*pi)))
        for i in range(12):
            for j in range(48):
                a=i*49+j;faces.append((a,a+1,a+50,a+49))
        frog.mesh('Tympanic skin '+side,vertices,faces,uv,[trunk_skin(p) for p in vertices],frog.body_mat)
        rim, radii = [], []
        for t in np.linspace(0,1,49):
            point = cheek_surface(-.044+.0125*t+.0057*sin(pi*t), .86-.78*t)
            point.x += sign*.00006
            rim.append(point)
            radii.append(.00004+.00022*sin(pi*t)**2)
        fold=frog.tube('Tympanic fold '+side,rim,radii,['Head']*(len(rim)-1),frog.fold_mat,1,8)
        spine=fold.vertex_groups.new(name='DEF-spine.003');head=fold.vertex_groups['Head']
        for vertex in fold.data.vertices:
            weights=trunk_skin(vertex.co)
            head.add([vertex.index],weights['Head'],'REPLACE');spine.add([vertex.index],weights['DEF-spine.003'],'REPLACE')
