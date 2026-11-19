"""Authored leaf-frog facial proportions and small anatomical surfaces. MIT.

Photographs guide proportions only. No image, mesh or animation is read here.
"""
from math import sin, cos, pi, sqrt

import numpy as np
from mathutils import Vector

EYE_RADIUS = .0085
EYE_ASPECT = (.94, 1.02, .72)
EYE_APERTURE = 1.31
BODY_Y_RANGE = (-.083,.073)
NARIS_XY = (.0160,-.0725)
FACE_SECTIONS = [
    [-.083,.0045,.0440,.0475],[-.078,.0125,.0440,.0515],
    [-.069,.0215,.0450,.0560],[-.049,.0325,.0460,.0590],
    [-.030,.0315,.0405,.0570]]


def eye_frame(sign):
    normal = Vector((sign*.76,-.64,.10)).normalized()
    horizontal = normal.cross(Vector((0,0,1))).normalized()
    return normal,horizontal,horizontal.cross(normal).normalized()


def lid_axis(sign):
    normal = eye_frame(sign)[0]
    return (Vector((0,0,1))*.18-normal).normalized()


def shorten_muzzle(point):
    point = Vector(point)
    if point.y<-.061:
        front = min(1,max(0,(point.y+.083)/.008));front = front*front*(3-2*front)
        t = min(1,max(0,(point.y+.083)/.022));t = t*t*(3-2*t)
        point.y += .0025*(1-t)
        point.y += .0006*(point.x/.012)**2*(1-front)
    return point


def orbital_recess(point,centers):
    """Keep the continuous cranial skin behind the elliptical eye apertures."""
    point=Vector(point)
    for sign,center in centers:
        normal,horizontal,vertical=eye_frame(sign);delta=point-center
        radius=EYE_RADIUS*sin(EYE_APERTURE)
        rho=sqrt((delta.dot(horizontal)/EYE_ASPECT[0])**2
                 +(delta.dot(vertical)/EYE_ASPECT[1])**2)/radius
        if rho>=1.18:continue
        blend=min(1,max(0,(1.18-rho)/.18));blend=blend*blend*(3-2*blend)
        point-=normal*(max(0,delta.dot(normal)-.0010)*blend)
    return point


def add_features(frog):
    for side,sign in [('L',-1),('R',1)]:
        center = frog.bones['FX_eye.'+side][0];n,u,v = eye_frame(sign)
        frog.cap('Green orbital socket '+side,center,-n,EYE_RADIUS+.0003,pi-1.25,
                 frog.orbit_mat,'Head',24,48,aspect=EYE_ASPECT,disk_uv=False)
        frog.cap('Red corneal surface '+side,center,n,EYE_RADIUS,EYE_APERTURE,
                 frog.iris,'FX_eye.'+side,24,64,aspect=EYE_ASPECT)
        frog.cap('Mobile upper eyelid '+side,center,lid_axis(sign),EYE_RADIUS+.0005,1.36,
                 frog.orbit_mat,'Lid.'+side,24,48,aspect=EYE_ASPECT)
        ring = [center+n*((EYE_RADIUS+.00025)*cos(EYE_APERTURE)*EYE_ASPECT[2])
                +(u*(cos(a)*EYE_ASPECT[0])+v*(sin(a)*EYE_ASPECT[1]))*((EYE_RADIUS+.00025)*sin(EYE_APERTURE))
                for a in np.linspace(0,2*pi,81)]
        frog.tube('Fine eye rim '+side,ring,[.00013]*len(ring),['Head']*(len(ring)-1),frog.rim_mat,1,8)
        lip = []
        for y in np.linspace(-.0827,-.034,48):
            x = sign*frog.jaw_width(y)
            lip.append((x,y,frog.body_height(x,y,False)-.00005))
        frog.tube('Mouth commissure '+side,lip,[.00017]*len(lip),['Head']*(len(lip)-1),frog.dark,1,8)
        # Small, low-profile nares sit on the snout rather than on dark bumps.
        x,y = sign*NARIS_XY[0],NARIS_XY[1];z = frog.body_height(x,y)
        delta = .0001
        gx = (frog.body_height(x+delta,y)-frog.body_height(x-delta,y))/(2*delta)
        gy = (frog.body_height(x,y+delta)-frog.body_height(x,y-delta))/(2*delta)
        normal = Vector((-gx,-gy,1)).normalized()
        rotation = Vector((0,0,1)).rotation_difference(normal).to_matrix()
        center_naris = Vector((x,y,z))+normal*.00012
        frog.ellipsoid('Nostril '+side,center_naris,(.00065,.00043,.00008),frog.dark,'Head',10,24,rotation)
        rim = []
        for a in np.linspace(0,2*pi,33):
            point = Vector((x,y,z))+rotation@Vector((.00078*cos(a),.00055*sin(a),.00004))
            rim.append(point)
        frog.tube('Soft naris rim '+side,rim,[.00009]*len(rim),['Head']*(len(rim)-1),frog.fold_mat,1,8)
        # A flush membrane and tapered upper fold replace a raised round disc.
        def cheek(radius,angle):
            y = -.0325+.0034*radius*cos(angle)
            theta = .17+.14*radius*sin(angle)
            width = frog.section_at(y)[1]
            x = sign*width*cos(theta)
            return Vector((x+sign*.00004,y,frog.body_height(x,y,theta>=0)))
        def trunk_skin(point):
            t=min(1,max(0,(point.y+.038)/.023));head=1-t*t*(3-2*t)
            return {'Head':head,'DEF-spine.003':1-head}
        vertices=[];uv=[];faces=[]
        for i in range(13):
            for j in range(49):
                a=2*pi*j/48;r=i/12
                point=cheek(r,a);vertices.append(point)
                theta=.17+.14*r*sin(a)
                uv.append(((point.y-BODY_Y_RANGE[0])/(BODY_Y_RANGE[1]-BODY_Y_RANGE[0]),theta/(2*pi) if sign>0 else .5-theta/(2*pi)))
        for i in range(12):
            for j in range(48):
                a=i*49+j;faces.append((a,a+1,a+50,a+49))
        frog.mesh('Tympanic skin '+side,vertices,faces,uv,[trunk_skin(p) for p in vertices],frog.body_mat)
        rim = [cheek(1,a) for a in np.linspace(-.08,pi+.08,49)]
        radii = [.000035+.00013*sin(pi*i/(len(rim)-1))**2 for i in range(len(rim))]
        fold=frog.tube('Tympanic fold '+side,rim,radii,['Head']*(len(rim)-1),frog.fold_mat,1,8)
        spine=fold.vertex_groups.new(name='DEF-spine.003');head=fold.vertex_groups['Head']
        for vertex in fold.data.vertices:
            weights=trunk_skin(vertex.co)
            head.add([vertex.index],weights['Head'],'REPLACE');spine.add([vertex.index],weights['DEF-spine.003'],'REPLACE')
