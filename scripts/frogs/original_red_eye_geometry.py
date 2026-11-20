"""Original red-eyed leaf-frog surfaces, rig and painted textures. MIT.

All coordinates, topology and pixels are generated here. No downloaded mesh,
rig, animation or photograph is read by this module. Coordinates are metres,
Blender Z up / -Y forward. The reference links are documented separately.
"""
from math import cos, exp, sin, pi, sqrt
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from original_red_eye_feet import adhesive_pad, digital_web
from original_red_eye_face import BODY_Y_RANGE, NARIS_XY, FACE_SECTIONS, shorten_muzzle, orbital_recess, add_features


def profile(controls, y):
    """C1 Hermite sections with derivatives measured along the actual axis."""
    i = min(len(controls)-2, max(0, int(np.searchsorted(controls[:, 0], y)-1)))
    a, b = controls[i], controls[i+1]
    prior, after = controls[max(0, i-1)], controls[min(len(controls)-1, i+2)]
    length = b[0]-a[0];t = np.clip((y-a[0])/length, 0, 1)
    left = (b-prior)/(b[0]-prior[0]);right = (after-a)/(after[0]-a[0])
    return ((2*t**3-3*t*t+1)*a+(t**3-2*t*t+t)*length*left
            +(-2*t**3+3*t*t)*b+(t**3-t*t)*length*right)


def smooth(a, b, value):
    t = np.clip((value-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def noise(u, v, seed=9, count=18):
    rng = np.random.default_rng(seed)
    result = np.zeros_like(u+v)
    for _ in range(count):
        a, b = rng.uniform(4, 180, 2)
        result += np.sin(u*a+v*b+rng.uniform(0, 6.28))/count
    return result


def value_noise(u, v, columns, rows, seed):
    """Interpolated random glands, avoiding repetitive sine-wave skin grooves."""
    grid = np.random.default_rng(seed).uniform(-1, 1, (rows+2, columns+2))
    x, y = u*columns, v*rows
    ix, iy = x.astype(int), y.astype(int)
    fx, fy = x-ix, y-iy
    fx = fx*fx*(3-2*fx);fy = fy*fy*(3-2*fy)
    return ((grid[iy, ix]*(1-fx)+grid[iy, ix+1]*fx)*(1-fy)
            +(grid[iy+1, ix]*(1-fx)+grid[iy+1, ix+1]*fx)*fy)


def image(name, pixels):
    height, width = pixels.shape[:2]
    img = bpy.data.images.new(name, width=width, height=height, alpha=True)
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[:, :, :pixels.shape[2]] = pixels
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


def painted_maps(name, width, height, kind):
    u, v = np.meshgrid(np.linspace(0, 1, width), np.linspace(0, 1, height))
    grain = value_noise(u, v, 32, 16, 9)*.6+value_noise(u, v, 96, 48, 19)*.4
    pores = value_noise(u, v, width//3, height//3, 71)*.6+value_noise(u, v, width//7, height//7, 72)*.4
    if kind == 'digits':
        rgb = np.broadcast_to([.91, .35, .065], (height, width, 3)).copy()
        rgb *= (1+.11*grain+.03*pores)[:, :, None]
        du, dv = np.gradient(pores)
        normal = image(name+' micro normal', np.clip(np.stack([.5-du*.18, .5-dv*.18, np.ones_like(u)], axis=-1), 0, 1))
        normal.colorspace_settings.name = 'Non-Color'
        rough = image(name+' roughness', np.repeat((.43+.065*grain+.015*pores)[:, :, None], 3, axis=2))
        rough.colorspace_settings.name = 'Non-Color'
        return image(name+' color', np.clip(rgb, 0, 1)), normal, rough
    if kind == 'iris':
        x, y = (u-.5)*2, (v-.5)*2
        radius = np.sqrt(x*x+y*y)
        angle = np.arctan2(y, x)
        crypts = value_noise(u,v,70,70,216)*.65+value_noise(u,v,200,200,217)*.35
        fiber = np.sin(angle*137+radius*23+crypts*7)*.28+np.sin(angle*241-radius*31+grain*9)*.12
        pupil_width = .25*np.maximum(0,1-(y/.61)**2)**.50
        gold = np.exp(-((abs(x)-pupil_width-.045)/.045)**2)*(1-smooth(.56,.72,abs(y)))
        orange = smooth(-.25,.55,crypts+fiber)*.55+.30*gold
        rgb = np.stack([.52+.20*orange+.12*crypts+.07*fiber,
                        .035+.115*orange+.020*crypts,
                        .008+.012*orange],axis=-1)
        rgb[(abs(x)<pupil_width)&(abs(y)<.61)] = [.002,.003,.002]
        rim = smooth(.96,.997,radius)
        rgb = rgb*(1-rim[:,:,None])+np.array([.034,.018,.009])*rim[:,:,None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    if kind == 'ventral':
        rgb = np.broadcast_to([.70, .70, .57], (height, width, 3)).copy()
        rgb *= (1+.045*grain+.025*pores)[:, :, None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    dorsal = np.sin(v*2*pi)
    green = np.array([.075, .40, .018]) if kind == 'body' else np.array([.07, .37, .016])
    rgb = np.broadcast_to(green, (height, width, 3)).copy()
    rgb *= (1+.09*grain+.045*pores)[:, :, None]
    if kind == 'orbital':return image(name+' color', np.clip(rgb, 0, 1)), None, None
    belly = 1-smooth(-.75, -.40, dorsal)
    rgb = rgb*(1-belly[:, :, None])+np.array([.83, .83, .62])*belly[:, :, None]
    if kind == 'body':
        flank = smooth(-.72, -.49, dorsal)*(1-smooth(.12, .25, dorsal))
        flank *= smooth(.40, .48, u)*(1-smooth(.88, .98, u))
        blue = np.stack([.045+.025*grain, .18+.035*grain, .43+.06*grain], axis=-1)
        phase = u*59+.6*np.sin(v*12)+grain*.8
        bars = smooth(.83, .95, np.sin(phase))
        blue = blue*(1-bars[:, :, None])+np.array([.88, .77, .28])*bars[:, :, None]
        rgb = rgb*(1-flank[:, :, None])+blue*flank[:, :, None]
        edge = np.exp(-((dorsal-(.21+.025*np.sin(u*56))) / .042)**2)
        edge *= smooth(.41, .49, u)*(1-smooth(.87, .97, u))
        rgb = rgb*(1-edge[:, :, None])+np.array([.87, .80, .29])*edge[:, :, None]
        # Small pigment flecks break up the muzzle's broad smooth highlight;
        # they change albedo rather than making the dorsal surface warty.
        shimmer = smooth(.50, .85, value_noise(u, v, 600, 300, 401))
        shimmer *= smooth(.05, .55, dorsal)*(.18+.16*(1-smooth(.15, .40, u)))
        rgb = rgb*(1-shimmer[:, :, None])+np.array([.55, .65, .50])*shimmer[:, :, None]
        rng = np.random.default_rng(801)
        for _ in range(24):
            a, b = rng.uniform(.25, .89), rng.uniform(.06, .43)
            fleck = np.exp(-((u-a)/.0022)**2-((v-b)/.0022)**2)*.65
            rgb = rgb*(1-fleck[:, :, None])+np.array([.85, .88, .58])*fleck[:, :, None]
        # The upper muzzle stays green to its closing edge; the articulated
        # lower jaw supplies the ivory lip, avoiding a second pale ledge.
        head = (1-smooth(.28,.35,u))*np.maximum(smooth(-.55,-.35,dorsal),1-smooth(.14,.20,u))
        glands = value_noise(u,v,460,220,448)
        pigment = smooth(.36,.74,glands+pores*.20)
        face = np.broadcast_to([.090,.355,.022],rgb.shape).copy()
        face *= (1+.10*grain+.04*glands)[:,:,None]
        face = face*(1-pigment[:,:,None]*.12)+np.array([.35,.44,.12])*pigment[:,:,None]*.12
        rgb = rgb*(1-head[:,:,None])+face*head[:,:,None]
        width = profile(np.asarray(FACE_SECTIONS),NARIS_XY[1])[1]
        naris_v = np.arccos(NARIS_XY[0]/width)/(2*pi)
        naris_u = (NARIS_XY[1]-BODY_Y_RANGE[0])/(BODY_Y_RANGE[1]-BODY_Y_RANGE[0])
        pits = sum(np.exp(-((u-naris_u)/.0040)**2-((v-center)/.0050)**2)
                   for center in [naris_v,.5-naris_v])
        rgb = rgb*(1-pits[:,:,None])+np.array([.005,.010,.003])*pits[:,:,None]
    else:
        blue = smooth(-.7, -.35, dorsal)*(1-smooth(.05, .35, dorsal))
        blue *= .30+.40*(1-smooth(.25, .90, u))
        rgb = rgb*(1-blue[:, :, None])+np.array([.045, .19, .39])*blue[:, :, None]
    du, dv = np.gradient(pores)
    normals = np.stack([.5-du*.25, .5-dv*.25, np.ones_like(u)], axis=-1)
    roughness = np.repeat((.40+.06*grain+.02*pores)[:, :, None], 3, axis=2)
    if kind=='body':
        gu,gv = np.gradient(glands)
        normals[:,:,:2] += np.stack([-gu*.11,-gv*.11],axis=-1)*head[:,:,None]
        face_roughness = .46+.04*grain+.015*glands
        roughness = roughness*(1-head[:,:,None])+face_roughness[:,:,None]*head[:,:,None]
    normal = image(name+' micro normal', np.clip(normals, 0, 1));normal.colorspace_settings.name = 'Non-Color'
    rough = image(name+' roughness', roughness);rough.colorspace_settings.name = 'Non-Color'
    return image(name+' color', np.clip(rgb, 0, 1)), normal, rough


def material(name, color, rough=.4, maps=None, coat=.06):
    mat = bpy.data.materials.new(name);mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    nodes = mat.node_tree.nodes;links = mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = rough
    shader.inputs['Coat Weight'].default_value = coat
    shader.inputs['Coat Roughness'].default_value = .15
    if maps:
        for img, target in zip(maps, ['Base Color', 'Normal', 'Roughness']):
            if img is None:continue
            texture = nodes.new('ShaderNodeTexImage');texture.image = img
            if target == 'Normal':
                normal = nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value = .32
                links.new(texture.outputs['Color'], normal.inputs['Color'])
                links.new(normal.outputs['Normal'], shader.inputs['Normal'])
            else:links.new(texture.outputs['Color'], shader.inputs[target])
    return mat


class Frog:
    def __init__(self):
        self.meshes = [];self.bones = {};self.rest = {};self.limbs = {};self.digits = {}
        self.body_mat = material('Original leaf-green dorsal skin', (.2, .55, .04),
                                 maps=painted_maps('Original trunk', 2048, 1024, 'body'))
        limb_maps = painted_maps('Original limbs', 1024, 512, 'limb')
        self.limb_mat = material('Original lime limb skin', (.07, .37, .016), maps=limb_maps)
        orbital = painted_maps('Original orbital skin', 512, 512, 'orbital')[0]
        self.orbit_mat = material('Green orbital skin', (.07, .37, .016),
                                  maps=(orbital, limb_maps[1], limb_maps[2]))
        self.orbit_mat.use_backface_culling = True
        self.orange = material('Orange digital pads', (.78, .15, .018), .43,
                               maps=painted_maps('Original digital skin', 512, 512, 'digits'), coat=.10)
        ventral = painted_maps('Original ventral skin', 512, 256, 'ventral')[0]
        self.cream = material('Ivory granular throat', (.50, .54, .31), .48,
                              maps=(ventral, limb_maps[1], limb_maps[2]))
        self.oral = material('Warm oral mucosa', (.32, .131, .119), .40, coat=.14)
        self.oral_dark = material('Recessed oral tissue', (.055, .025, .023), .53)
        self.pink = material('Tongue muscle', (.43, .15, .139), .36, coat=.20)
        self.dark = material('Mouth seam and nares', (.006, .011, .004), .5)
        self.fold_mat = material('Subtle facial folds',(.011,.086,.003),.50,coat=.03)
        self.rim_mat = material('Muted gold palpebral margin',(.34,.40,.13),.48,coat=.025)
        self.iris = material('Original red iris and vertical pupil', (.7, .07, .01), .17,
                             maps=painted_maps('Original iris', 1024, 1024, 'iris'), coat=.45)
        arm_data = bpy.data.armatures.new('Original leaf-frog joint definitions')
        self.arm = bpy.data.objects.new('Original_Red_Eye_Rig', arm_data)
        bpy.context.collection.objects.link(self.arm)
        bpy.context.view_layer.objects.active = self.arm;self.arm.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        self.bone('root', (0, 0, 0), (0, 0, .015))
        self.bone('DEF-spine.003', (0, .025, .042), (0, -.022, .054), 'root')
        self.bone('Head', (0, -.022, .054), (0, -.069, .057), 'DEF-spine.003')
        self.bone('FX-jaw', (0, -.024, .043), (0, -.072, .043), 'Head')
        self.bone('Throat', (0, -.035, .0405), (0, -.052, .0390), 'FX-jaw')
        self.bone('Tongue', (0, -.068, .044), (0, -.049, .045), 'FX-jaw')
        self.bone('TongueTip', (0, -.049, .045), (0, -.039, .046), 'Tongue')
        for side, sign in [('L', -1), ('R', 1)]:
            shoulder = Vector((sign*.028, -.024, .047))
            # In the resting crouch, the elbows support the shoulders while
            # the knees fold forward and the shins lie alongside the flank.
            elbow = Vector((sign*.042, -.013, .021))
            wrist = Vector((sign*.046, -.041, .007))
            hand = Vector((sign*.048, -.049, .005))
            hip = Vector((sign*.021, .044, .0415))
            knee = Vector((sign*.038, -.001, .028))
            ankle = Vector((sign*.042, .059, .014))
            heel = Vector((sign*.039, .026, .007))
            foot = Vector((sign*.042, .0095, .005))
            for label, points, names in [
                ('arm', [shoulder, elbow, wrist, hand], ['upper_arm', 'forearm', 'hand']),
                ('leg', [hip, knee, ankle, heel, foot], ['thigh', 'shin', 'tarsus', 'foot'])]:
                parent = 'DEF-spine.003'
                full = []
                for i, name in enumerate(names):
                    name = 'DEF-'+name+'.'+side
                    self.bone(name, points[i], points[i+1], parent);parent = name;full.append(name)
                self.limbs[(side, label)] = (points, full)
            for label, palm, parent, lengths in [
                ('hand', hand, 'DEF-hand.'+side, [.0168, .0232, .0240, .0184]),
                ('foot', foot, 'DEF-foot.'+side, [.0166, .0232, .0299, .0274, .0199])]:
                digits = []
                for i, length in enumerate(lengths):
                    fan = (i-(len(lengths)-1)/2)*.48
                    base = palm+Vector((sign*(i-(len(lengths)-1)/2)*.0028, -.002, 0))
                    end = base+Vector((sign*sin(fan)*length, -cos(fan)*length, -.0003))
                    middle = base.lerp(end, .55)+Vector((0, 0, .0016))
                    name = f'Digit_{label}_{i+1}.{side}'
                    self.bone(name, base, middle, parent)
                    self.bone(name+'_tip', middle, end, name)
                    digits.append(([base, middle, end], [name, name+'_tip']))
                self.digits[(side, label)] = digits
            center = Vector((sign*.0297, -.049, .0595))
            self.bone('FX_eye.'+side, center, center+Vector((0, -.01, 0)), 'Head')
            self.bone('Lid.'+side, center, center+Vector((0, 0, .01)), 'Head')
        bpy.ops.object.mode_set(mode='OBJECT')
        self.rest = {bone.name:bone.matrix_local.to_quaternion() for bone in arm_data.bones}

    def bone(self, name, head, tail, parent=None):
        bone = self.arm.data.edit_bones.new(name);bone.head = head;bone.tail = tail
        if parent:bone.parent = self.arm.data.edit_bones[parent]
        self.bones[name] = (Vector(head), Vector(tail))

    def mesh(self, name, vertices, faces, uv, weights, mat):
        if not name.startswith(('Continuous ','Orange ','hand ','foot ','Scalloped ')):
            vertices = [shorten_muzzle(point) for point in vertices]
        mesh = bpy.data.meshes.new(name);mesh.from_pydata(vertices, [], faces);mesh.update()
        obj = bpy.data.objects.new(name, mesh);bpy.context.collection.objects.link(obj)
        mesh.materials.append(mat)
        layer = mesh.uv_layers.new(name='Original analytic UV')
        for polygon in mesh.polygons:
            polygon.use_smooth = True
            for loop in polygon.loop_indices:layer.data[loop].uv = uv[mesh.loops[loop].vertex_index]
        groups = {}
        for index, entry in enumerate(weights):
            for bone, value in entry.items():
                if value <= 0:continue
                if bone not in groups:groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([index], float(value), 'REPLACE')
        modifier = obj.modifiers.new('Original skeletal skin', 'ARMATURE');modifier.object = self.arm
        obj.parent = self.arm;self.meshes.append(obj)
        return obj

    def ellipsoid(self, name, center, size, mat, bone, rings=14, segments=24, rotation=None):
        vertices = [];uv = [];faces = []
        for i in range(rings+1):
            phi = pi*i/rings
            for j in range(segments+1):
                theta = 2*pi*j/segments
                point = Vector((size[0]*sin(phi)*cos(theta), size[1]*sin(phi)*sin(theta), size[2]*cos(phi)))
                if rotation:point = rotation @ point
                point += Vector(center)
                vertices.append(point);uv.append((j/segments, i/rings))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1
                faces.append((a, b, b+1, a+1))
        return self.mesh(name, vertices, faces, uv, [{bone:1} for _ in vertices], mat)

    def section_at(self,y):
        return profile(self.body_sections,y)

    def body_height(self, x, y, upper=True, section=None):
        section = self.section_at(y) if section is None else section
        width, bottom, top = section[1:]
        s = sqrt(max(0, 1-(x/width)**2))*(1 if upper else -1)
        z = (top+bottom)/2+(top-bottom)/2*s
        if not upper:
            flat = bottom+(top-bottom)/2*(1-(-s)**.30)
            blend = float(1-smooth(-.032, -.012, y))
            z = z*(1-blend)+flat*blend
        else:
            # The flatter crown rolls into the canthus and cheek on either side.
            ratio = min(1,abs(x)/width)
            roof = top-.0012*(ratio/.72)**2
            cheek = top-.0012-(top-.0012-(top+bottom)/2)*(ratio-.72)/.28
            plane = .5*(roof+cheek-sqrt((roof-cheek)**2+.00060**2))
            planes = .29*float(1-smooth(-.053,-.033,y))
            z = z*(1-planes)+plane*planes
            # Broaden the brow toward the back of the skull so the eye
            # sits on a low ridge that fades into the shoulder.
            brow_y = y+.049
            brow_length = .012 if brow_y < 0 else .019
            brow = .0060*exp(-((abs(x)-.0250)/.013)**2-(brow_y/brow_length)**2)
            z += brow*float(smooth(0,.22,s))*(1-float(smooth(-.030,-.012,y)))
            if -.064 < y < -.022:
                # The forehead bridges the brows and rolls down toward the
                # snout and shoulders. Fade it out before the orbital rim.
                forehead = s**8
                crown = exp(-((y+.048)/.013)**2)
                taper = smooth(-.064,-.053,y)*(1-smooth(-.034,-.022,y))
                z += .00435*forehead*crown*taper
            # The canthus follows the edge between the upper snout and cheek.
            # A shallow falloff on its outer side defines that change of plane.
            if -.080 < y < -.045:
                along = float(smooth(-.076,-.052,y))
                offset = abs(x)-width*(.62+.14*along)
                envelope = float(smooth(-.080,-.074,y)*(1-smooth(-.055,-.045,y)))
                crest = .00165*exp(-(offset/.0034)**2)
                flank = .00075*exp(-((offset-.0054)/.0036)**2)
                z += envelope*(crest-flank)*s**.4
            # Both nares are sculpted into the same surface as the muzzle.
            if abs(y-NARIS_XY[1]) < .006:
                radius = sqrt(((abs(x)-NARIS_XY[0])/.00185)**2+((y-NARIS_XY[1])/.0022)**2)
                if radius < 3:
                    basin = -.00065*exp(-1.5*radius**2)
                    edge = .00025*exp(-((radius-1.10)/.42)**2)
                    z += (basin+edge)*s**.4
            z += .0012*np.exp(-(x/.006)**2-((y-.041)/.027)**2)*float(smooth(-.003,.013,y))*s**.6
        if -.055 < y < -.020:
            # The lip turns upward behind the eye. The same relief is used on
            # both halves of the head and on the fitted closing jaw.
            corner = exp(-((y+.0345)/.0068)**2)
            outer_cheek = exp(-(s/.41)**2)
            taper = smooth(-.055,-.049,y)*(1-smooth(-.025,-.020,y))
            z += .0017*corner*outer_cheek*taper
        return float(z)

    def body(self):
        # Smooth longitudinal sections include the head: there is no neck seam.
        controls = np.array([*FACE_SECTIONS,[-.008,.0255,.0265,.0579],
            [.020,.0225,.0265,.0528],[.047,.0205,.0290,.0515],
            [.058,.0165,.0305,.0480],[.066,.0120,.0315,.0455],
            [.071,.0065,.0335,.0420],[BODY_Y_RANGE[1],.0001,.0370,.0370]])
        self.body_sections = controls
        vertices = [];faces = [];uv = [];weights = []
        base_y = np.linspace(controls[0,0], controls[-1,0], 97)
        midpoints = (base_y[:-1]+base_y[1:])*.5
        near_nares = abs(midpoints-NARIS_XY[1]) < .004
        near_tip = midpoints < controls[0,0]+.005
        near_orbits = (midpoints > -.065) & (midpoints < -.035)
        rows = np.sort(np.concatenate((base_y,midpoints[near_nares | near_tip | near_orbits])))
        rings, segments = len(rows)-1, 96
        for y in rows:
            u = (y-controls[0,0])/(controls[-1,0]-controls[0,0])
            section = self.section_at(y)
            width, bottom, top = section[1:]
            for j in range(segments+1):
                theta = 2*pi*j/segments;x = width*cos(theta)
                z = self.body_height(x, y, sin(theta)>=0, section)
                centers=[(sign,self.bones['FX_eye.'+side][0]) for side,sign in [('L',-1),('R',1)]]
                vertices.append(orbital_recess((x,y,z),centers));uv.append((u, j/segments))
                head = float(1-smooth(-.038, -.015, y))
                weights.append({'Head':head, 'DEF-spine.003':1-head})
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1
                faces.append((a, b, b+1, a+1))
        faces.extend([tuple(reversed(range(segments))), tuple(rings*(segments+1)+j for j in range(segments))])
        return self.mesh('Original continuous trunk and muzzle', vertices, faces, uv, weights, self.body_mat)

    def tube(self, name, points, radii, bones, mat, rings_per_span=8, segments=18, bulges=None, flatten=None, crease=False, attachment=None):
        points = [Vector(p) for p in points]
        vertices = [];uv = [];weights = [];faces = []
        total = (len(points)-1)*rings_per_span
        for ring in range(total+1):
            value = ring/rings_per_span;span = min(len(points)-2, int(value));t = value-span
            p0 = points[max(0, span-1)];p1 = points[span];p2 = points[span+1];p3 = points[min(len(points)-1, span+2)]
            point = .5*(2*p1+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
            root = 0.0
            if attachment:
                sign, inset = attachment
                # Bury the closed root within the torso; the emerging muscle
                # follows the original joint landmarks without moving bones.
                root = float(1-smooth(0, .70, value))
                point.x -= sign*inset*root
                if span==0:point.x += sign*.0010*sin(pi*t)**2
            tangent = (-p0+p2)+(2*p0-5*p1+4*p2-p3)*(2*t)+(-p0+3*p1-3*p2+p3)*(3*t*t)
            if attachment and len(points)==5:
                # A small lateral soft-tissue roll rounds the ankle hairpin;
                # its derivative keeps the loft frame tangent to that roll.
                roll = np.exp(-((value-2)/.20)**2)
                shift = Vector((sign*.0030,0,.0010))
                point += shift*roll
                tangent += shift*(-4*(value-2)/.20**2*roll)
            tangent.normalize();axis = tangent.cross(Vector((0, 0, 1)))
            if axis.length < .01:axis = tangent.cross(Vector((0, 1, 0)))
            axis.normalize();up = tangent.cross(axis).normalized()
            if up.z < 0:up = -up;axis = -axis
            radius = radii[span]*(1-t)+radii[span+1]*t
            if bulges:radius *= 1+bulges[span]*sin(pi*t)**2
            vertical = .91 if flatten is None else flatten[span]*(1-t)+flatten[span+1]*t
            if span == 0:radius *= .75+.25*sin(min(1, t*3)*pi/2)
            current = min(span, len(bones)-1)
            skin = {bones[current]:1.0}
            if span > 0 and t < .25 and bones[current] != bones[current-1]:
                mix = .5*(1-t/.25);skin = {bones[current]:1-mix, bones[current-1]:mix}
            elif current+1 < len(bones) and t > .75 and bones[current] != bones[current+1]:
                mix = .5*(t-.75)/.25;skin = {bones[current]:1-mix, bones[current+1]:mix}
            for j in range(segments+1):
                angle = 2*pi*j/segments
                radial = radius
                if crease:radial *= 1-.10*np.exp(-((value-1)/.10)**2)*max(0,sin(angle))
                if attachment and len(points)==5:
                    radial *= 1+.30*np.exp(-((value-2)/.18)**2)
                vertex = point+axis*(cos(angle)*radial)+up*(sin(angle)*radial*vertical)
                entry = skin
                if root>0:
                    # Match the trunk's longitudinal Head/spine skin field at
                    # the actual vertex, then fade into the moving upper limb.
                    head = float(1-smooth(-.038, -.015, vertex.y))
                    entry = {bone:weight*(1-root) for bone,weight in skin.items()}
                    entry.update({'Head':root*head, 'DEF-spine.003':root*(1-head)})
                vertices.append(vertex)
                uv.append((ring/total, j/segments));weights.append(entry)
        for i in range(total):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1;faces.append((a, a+1, b+1, b))
        faces.extend([tuple(reversed(range(segments))), tuple(total*(segments+1)+j for j in range(segments))])
        return self.mesh(name, vertices, faces, uv, weights, mat)

    def cap(self, name, center, direction, radius, angle, mat, bone, rings=20, segments=64, aspect=(1, 1, 1), disk_uv=True):
        n = Vector(direction).normalized();u = n.cross(Vector((0, 0, 1))).normalized();v = u.cross(n).normalized()
        vertices = [];uv = [];faces = []
        for i in range(rings+1):
            phi = angle*i/rings
            for j in range(segments+1):
                theta = 2*pi*j/segments
                radial = u*(cos(theta)*aspect[0])+v*(sin(theta)*aspect[1])
                vertices.append(Vector(center)+radius*(n*(cos(phi)*aspect[2])+radial*sin(phi)))
                if disk_uv:
                    fraction = sin(phi)/sin(angle)
                    uv.append((.5+.5*fraction*cos(theta), .5+.5*fraction*sin(theta)))
                else:uv.append((j/segments, i/rings))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1;faces.append((a, a+1, b+1, b))
        return self.mesh(name, vertices, faces, uv, [{bone:1} for _ in vertices], mat)

    def jaw_width(self,y):
        # Interpolated jaw widths must remain inside the closing upper lip,
        # including between controls near the rear mouth corner.
        return min(float(profile(self.jaw_sections,y)[1]),.975*self.section_at(y)[1])

    def jaw(self):
        sections = np.array([[-.0829, .0075, .0448], [-.078, .0160, .0440],
                             [-.069, .0240, .0414], [-.049, .0355, .037],
                             [-.029, .0318, .037], [-.023, .0002, .037]])
        self.jaw_sections = sections
        vertices = [];faces = [];uv = [];inside = []
        base_y = np.linspace(sections[0,0], sections[-1,0], 49)
        midpoints = (base_y[:-1]+base_y[1:])*.5
        rows = np.sort(np.concatenate((base_y,midpoints[midpoints<sections[0,0]+.004])))
        rings, segments = len(rows)-1, 64
        for y in rows:
            u = (y-sections[0,0])/(sections[-1,0]-sections[0,0])
            width = self.jaw_width(y)
            # The front of the chin is rounded, with less depth by the hinge.
            tip = 1-smooth(-.080,-.062,y)
            depth = .00065+.00170*exp(-((y+.059)/.0155)**2)-.00043*tip
            chin = .00135*smooth(-.083,-.077,y)*(1-smooth(-.059,-.047,y))
            throat_join = .00165*exp(-((y+.041)/.0105)**2)*(1-smooth(-.030,-.024,y))
            inset = .00028*(1-smooth(-.082,-.069,y))
            oral_taper = float(smooth(-.080,-.067,y)*(1-smooth(-.034,-.024,y)))
            # Leave .48 mm of wall at the center of the shallower rear jaw.
            oral_depth = min(.00145,.00025+depth+.00030-.00048)
            for j in range(segments+1):
                angle = j/segments*2*pi
                x = width*cos(angle)
                s = sin(angle)
                surface = self.body_height(x,y,False)
                if s >= 0:
                    bowl = -oral_depth*s**2.6
                    rim = .00072*exp(-((s-.48)/.19)**2)
                    z = surface+.00030*sqrt(s)+oral_taper*(bowl+rim)*sqrt(s)
                else:
                    underside = -s
                    lateral_roll = sin(pi*underside)**2
                    z = surface-(.00025+depth+chin*underside)*sqrt(underside)-throat_join*lateral_roll
                # Seat the lip rim inside the curved nose at rest.
                z += inset*exp(-(s/.63)**2)
                vertices.append((x, y+.80*inset, z));uv.append((u, j/segments))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1
                faces.append((a, b, b+1, a+1));inside.append(sin((j+.5)/segments*2*pi)>.28)
        faces.extend([tuple(reversed(range(segments))), tuple(rings*(segments+1)+j for j in range(segments))])
        obj = self.mesh('Articulated jaw and recessed oral floor', vertices, faces, uv,
                        [{'FX-jaw':1} for _ in vertices], self.cream)
        obj.data.materials.append(self.oral)
        for polygon, oral in zip(obj.data.polygons, inside):polygon.material_index = 1 if oral else 0

    def palate(self):
        """Sculpt the inner upper lip and its paired folds into the roof."""
        vertices, faces, uv, tones, weights = [], [], [], [], []
        rings, segments = 36, 64
        for i in range(rings+1):
            y = -.0805+(.0805-.0229)*i/rings
            blend = float(smooth(-.033,-.0265,y))
            width = (1-blend)*.93*self.jaw_width(y)+blend*.73*self.section_at(y)[1]
            head = float(1-smooth(-.038,-.015,y))
            taper = float(smooth(-.0805,-.068,y)*(1-smooth(-.037,-.0275,y)))
            rear = exp(-((y+.0345)/.0035)**2)
            shade = 1-.77*float(smooth(-.034,-.024,y))
            for j in range(segments+1):
                across = 2*j/segments-1
                x = width*across
                margin = taper*exp(-((abs(across)-.81)/.108)**2)
                rear_fold = rear*exp(-((abs(across)-.52)/.31)**2)
                relief = .00054*margin+.000145*rear_fold
                z = self.body_height(x,y,False)-.00008-.000075*blend-relief
                vertices.append((x,y,z))
                uv.append((j/segments,i/rings))
                weights.append({'Head':head,'DEF-spine.003':1-head})
                tint = .85*margin+.35*rear_fold
                tones.append((shade*(.290+.10*tint),shade*(.108+.080*tint),
                              shade*(.099+.060*tint)))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1;faces.append((a,b,b+1,a+1))
        tint = image('Original palate color',np.asarray(tones).reshape(rings+1,segments+1,3))
        palate_mat = material('Palate mucosa',(.290,.108,.099),.42,maps=(tint,None,None),coat=.13)
        self.mesh('Recessed curved palate',vertices,faces,uv,weights,palate_mat)

    def gular_sac(self):
        """Fit the inflatable throat to the underside of the resting chin."""
        vertices, faces, uv, weights = [], [], [], []
        rings, segments = 24, 48
        for i in range(rings+1):
            phi = pi*i/rings
            dome = cos(phi)
            radius = sin(phi)
            belly = max(0,-dome)
            inflate = float(smooth(.04,.79,belly))
            for j in range(segments+1):
                theta = 2*pi*j/segments
                y = -.0465+.0225*radius*sin(theta)
                neck = float(smooth(-.044,-.024,y))
                x = .0250*(1-.29*neck)*radius*cos(theta)
                front = float(smooth(-.069,-.050,y))
                depth = .00625*belly**1.4*(.68+.32*front)*(1-.21*neck)
                # Recess the medial roof below the oral floor while retaining
                # the outer throat contour where it meets the jaw.
                medial = 1-float(smooth(.011,.022,abs(x)))
                roof_inset = medial*(.0010*(1-belly)+.00105*max(0,dome))
                z = self.body_height(x,y,False)-.00090+.00048*max(0,dome)-roof_inset-depth
                vertices.append((x,y,z))
                uv.append((j/segments,i/rings))
                # The rim rides with the jaw. The center expands with the sac.
                weights.append({'FX-jaw':1-inflate, 'Throat':inflate})
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j
                b = a+segments+1
                faces.append((a,b,b+1,a+1))
        self.mesh('Gular breathing sac', vertices, faces, uv, weights, self.cream)

    def tongue(self):
        """Loft one pliable surface from the attached base to the rounded pad."""
        center = self.body_height(0,-.056,False)+.00205
        sections = np.array([
            [-.0718,.00000,-.00255,.00000],
            [-.0698,.00340,-.00235,.00091],
            [-.0640,.00565,-.00140,.00127],
            [-.0565,.00505, .00010,.00135],
            [-.0500,.00465, .00020,.00136],
            [-.0470,.00545, .00006,.00153],
            [-.0430,.00705, .00008,.00158],
            [-.0395,.00640, .00007,.00134],
            [-.0366,.00390,-.00002,.00092],
            [-.0352,.00000,-.00016,.00000],
        ])
        rings, segments = 42, 36
        vertices, faces, uv, weights = [], [], [], []
        for i,y in enumerate(np.linspace(sections[0,0],sections[-1,0],rings+1)):
            _,width,height,depth = profile(sections,y)
            anchor = float(1-smooth(-.0705,-.0625,y))
            tip = float(smooth(-.052,-.0455,y))
            skin = {'FX-jaw':anchor,'Tongue':(1-anchor)*(1-tip),'TongueTip':(1-anchor)*tip}
            for j in range(segments+1):
                angle = 2*pi*j/segments
                vertices.append((width*cos(angle),y,center+height+depth*sin(angle)))
                uv.append((i/rings,j/segments))
                weights.append(skin)
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j
                b = a+segments+1
                faces.append((a,b,b+1,a+1))
        self.mesh('Articulated tongue',vertices,faces,uv,weights,self.pink)

    def features(self):
        self.jaw()
        self.palate()
        self.gular_sac()
        self.tongue()
        add_features(self)

    def limbs_and_digits(self):
        for (side, label), (points, bones) in self.limbs.items():
            if label == 'arm':
                radii = [.0059, .0041, .0028, .0033];bulges = [.18, .30, .0];flatten = [.84,.78,.65,.32]
                inset = .0095
            else:
                radii = [.0084, .0048, .0035, .0030, .0042];bulges = [.18, .20, .05, .0];flatten = [.78,.76,.76,.60,.30]
                inset = .0100
            self.tube('Continuous '+label+' '+side, points, radii, bones, self.limb_mat, 24 if label=='leg' else 12, 24, bulges, flatten, True,
                      (-1 if side=='L' else 1, inset))
            palm = points[-1]
            size = (.0058,.0056,.00165) if label=='arm' else (.0062,.0057,.00165)
            self.ellipsoid('Orange '+label+' palm '+side, palm+Vector((0,0,.00025)), size, self.orange, bones[-1])
        for (side, label), digits in self.digits.items():
            sizes = [.84,1.0,1.03,.91] if label=='hand' else [.80,.93,1.06,1.0,.88]
            for number, (points, bones) in enumerate(digits, 1):
                size = sizes[number-1]
                self.tube(f'{label} digit {number} {side}', points, [r*size for r in [.00145,.00110,.00125]], bones, self.orange, 10, 16, [.16,.12], [.88,.84,.65], True)
                adhesive_pad(self, f'{label} adhesive disc {number} {side}', points, bones[-1], size*(.82 if label=='hand' else .85))
            digital_web(self, side, label, digits)

    def build(self):
        self.body();self.limbs_and_digits();self.features()
        self.arm['provenance'] = 'Original parametric mesh, painted pixels, joint layout and motions; MIT. No imported model data.'
        self.arm['species'] = 'Agalychnis callidryas'
        self.arm['model_revision'] = 'original-red-eye-v30'
        self.arm['forward_axis'] = 'Blender -Y, glTF +Z'
        return self
