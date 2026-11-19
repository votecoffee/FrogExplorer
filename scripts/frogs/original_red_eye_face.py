"""Authored leaf-frog facial proportions and small anatomical surfaces. MIT.

Photographs guide proportions only. No image, mesh or animation is read here.
"""
from math import sin, cos, exp, pi, sqrt

import numpy as np
from mathutils import Vector

EYE_RADIUS = .0085
EYE_ASPECT = (1.025, 1.00, .78)
EYE_APERTURE = 1.31
BODY_Y_RANGE = (-.083,.073)
NARIS_XY = (.0140,-.0740)
FACE_SECTIONS = [
    [-.083,.0064,.0444,.0481],[-.078,.0153,.0445,.0527],
    [-.069,.0231,.0450,.0572],[-.049,.0325,.0459,.0628],
    [-.030,.0306,.0405,.0612]]


def eye_frame(sign):
    normal = Vector((sign*.72,-.695,.10)).normalized()
    horizontal = normal.cross(Vector((0,0,1))).normalized()
    return normal,horizontal,horizontal.cross(normal).normalized()


def lid_axis(sign):
    normal = eye_frame(sign)[0]
    return (Vector((0,0,1))*.18-normal).normalized()


def shorten_muzzle(point):
    """Shape the same shortened, rounded taper on the muzzle and jaw."""
    point = Vector(point)
    if point.y<-.061:
        front = min(1,max(0,(point.y+.083)/.008));front = front*front*(3-2*front)
        t = min(1,max(0,(point.y+.083)/.022));t = t*t*(3-2*t)
        point.y += .0072*(1-t)
        tip = 1-front
        rounded_side = (point.x/.0095)**2
        point.y += .0012*tip*rounded_side/(.30+rounded_side)
        point.x *= 1-.18*(1-t)
    return point


def orbital_recess(point,centers):
    """Recess the iris opening and roll the surrounding cheek into the socket."""
    point=Vector(point)
    for sign,center in centers:
        normal,horizontal,vertical=eye_frame(sign);delta=point-center
        radius=EYE_RADIUS*sin(EYE_APERTURE)
        rho=sqrt((delta.dot(horizontal)/EYE_ASPECT[0])**2
                 +(delta.dot(vertical)/EYE_ASPECT[1])**2)/radius
        if rho >= 1.60:
            continue
        depth = delta.dot(normal)
        blend = min(1, max(0, (1.18-rho)/.18))
        point -= normal*max(0, depth-.0010)*blend**2*(3-2*blend)
        # The lower orbital margin rises out of the cheek and fades into the
        # brow. It belongs to the continuous head, outside the iris opening.
        margin = min(1, max(0, (rho-1.02)/.58))
        lower = min(1, max(0, -delta.dot(vertical)/radius))
        roll = .0015*sin(pi*margin)**2*(.34+.66*lower)
        point += normal*roll*exp(-((depth+.001)/.0065)**2)
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
        depth = -radius*cos(phi)*EYE_ASPECT[2]-.0014*blend
        for j in range(segments+1):
            angle = 2*pi*j/segments
            height = sin(angle)
            spread = 1+blend*(.12*max(0,-height)-.09*max(0,height))
            radial = (-horizontal*(cos(angle)*EYE_ASPECT[0])
                      +vertical*(height*EYE_ASPECT[1]))
            vertices.append(center+normal*depth+radial*(radius*sin(phi)*spread))
            uv.append((j/segments,t))
    for i in range(rings):
        for j in range(segments):
            a = i*(segments+1)+j
            b = a+segments+1
            faces.append((a,a+1,b+1,b))
    frog.mesh('Green orbital socket '+side, vertices, faces, uv,
              [{'Head':1} for _ in vertices], frog.orbit_mat)


def add_features(frog):
    for side,sign in [('L',-1),('R',1)]:
        center = frog.bones['FX_eye.'+side][0];n,u,v = eye_frame(sign)
        add_orbital_socket(frog, side, center, n, u, v)
        frog.cap('Red corneal surface '+side,center,n,EYE_RADIUS,EYE_APERTURE,
                 frog.iris,'FX_eye.'+side,24,64,aspect=EYE_ASPECT)
        frog.cap('Mobile upper eyelid '+side,center,lid_axis(sign),EYE_RADIUS+.0005,1.36,
                 frog.orbit_mat,'Lid.'+side,24,48,aspect=EYE_ASPECT)
        ring = [center+n*((EYE_RADIUS+.00025)*cos(EYE_APERTURE)*EYE_ASPECT[2])
                +(u*(cos(a)*EYE_ASPECT[0])+v*(sin(a)*EYE_ASPECT[1]))*((EYE_RADIUS+.00025)*sin(EYE_APERTURE))
                for a in np.linspace(0,2*pi,81)]
        frog.tube('Fine eye rim '+side,ring,[.00013]*len(ring),['Head']*(len(ring)-1),frog.rim_mat,1,8)
        lip = []
        for y in np.linspace(-.0827,-.0315,48):
            x = sign*frog.jaw_width(y)
            lip.append((x,y,frog.body_height(x,y,False)-.00005))
        lip_radii = [.000055+.000075*sin(pi*i/(len(lip)-1)) for i in range(len(lip))]
        frog.tube('Mouth commissure '+side,lip,lip_radii,['Head']*(len(lip)-1),frog.dark,1,8)
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
