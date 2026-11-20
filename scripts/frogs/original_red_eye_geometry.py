"""Original red-eyed leaf-frog surfaces, rig and painted textures. MIT.

All coordinates, topology and pixels are generated here. No downloaded mesh,
rig, animation or photograph is read by this module. Coordinates are metres,
Blender Z up / -Y forward. The reference links are documented separately.
"""
from math import acos, cos, exp, sin, pi, sqrt
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from original_red_eye_feet import adhesive_pad, digital_web
from original_red_eye_face import (
    BODY_Y_RANGE, FACE_SECTIONS, NARIS_ANGLE, NARIS_Y, add_features,
    naris_radius, orbital_recess, shorten_muzzle, tympanic_radius, tympanic_relief,
)


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


def oral_floor_folds(along, arc):
    """Follow the shallow ridge of the inner lip and the groove behind it."""
    ridge_center = .48+.075*smooth(.14,.69,along)
    taper = smooth(.07,.28,along)*(1-smooth(.68,.90,along))
    taper *= smooth(.32,.43,arc)
    ridge = taper*np.exp(-((arc-ridge_center)/.145)**2)
    groove = taper*np.exp(-((arc-ridge_center-.23)/.113)**2)
    return ridge, groove


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
        thread = np.sin(139*angle+19*radius+2.9*grain)*.26
        thread += np.sin(223*angle-27*radius+5.8*crypts)*.12
        taper = np.maximum(0,1-(abs(y)/.655)**1.85)
        pupil_width = .183*taper**.65
        centerline = .027*y*taper
        distance = abs(x-centerline)-pupil_width
        pupil = (1-smooth(-.004,.006,distance))*(1-smooth(.633,.655,abs(y)))
        collar = np.exp(-((distance-.027)/.049)**2)*(1-smooth(.56,.71,abs(y)))
        orange = .46*(1-smooth(.22,.88,radius))+.49*collar
        fibers = (1-smooth(.88,1,radius))*(.081*thread+.078*crypts)
        rgb = np.stack([.61+.24*orange+fibers,
                        .050+.195*orange+.42*fibers,
                        .016+.017*orange+.07*fibers],axis=-1)
        rgb = rgb*(1-pupil[:,:,None])+np.array([.003,.005,.005])*pupil[:,:,None]
        rim = smooth(.939,.997,radius)
        rgb = rgb*(1-rim[:,:,None])+np.array([.042,.016,.026])*rim[:,:,None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    if kind in ('ventral', 'jaw'):
        rgb = np.broadcast_to([.70, .70, .57], (height, width, 3)).copy()
        if kind == 'jaw':
            side = np.sin(2*pi*v)
            # Confine the olive tint to the closing edge and run the pale
            # band into the throat instead of wrapping the jaw in white.
            under = smooth(-.92,-.22,side)*(1-smooth(-.36,-.04,side))
            olive = smooth(-.43,-.025,side)*(1-smooth(.14,.32,side))
            olive *= .42+.25*(1-smooth(.35,.85,u))
            tint = np.array([.57,.53,.44])
            rgb = rgb*(1-under[:,:,None])+tint*under[:,:,None]
            rgb = rgb*(1-olive[:,:,None])+np.array([.20,.32,.088])*olive[:,:,None]
        rgb *= (1+.045*grain+.025*pores)[:, :, None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    if kind == 'oral floor':
        arc = np.sin(2*pi*v)
        ridge, groove = oral_floor_folds(u, arc)
        rear = smooth(.48,.98,u)
        shade = .97-.24*rear-.07*groove+.10*ridge
        rgb = np.array([.58,.36,.32])*shade[:,:,None]
        rgb *= (1+.055*grain+.024*pores)[:,:,None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    if kind == 'tongue':
        upper = smooth(-.25,.80,np.sin(2*pi*v))
        pad = smooth(.67,.90,u)*(.48+.52*upper)
        root = 1-smooth(.06,.43,u)
        shaft = np.array([.65,.345,.325])
        tip = np.array([.79,.475,.43])
        rgb = shaft+pad[:,:,None]*(tip-shaft)
        rgb *= (1-.24*root+.052*grain+(.026+.028*pad)*pores)[:,:,None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    dorsal = np.sin(v*2*pi)
    green = np.array([.075, .40, .018]) if kind == 'body' else np.array([.07, .37, .016])
    rgb = np.broadcast_to(green, (height, width, 3)).copy()
    rgb *= (1+.09*grain+.045*pores)[:, :, None]
    if kind == 'orbital':
        # The mobile eyelid uses the untrimmed bottom of the texture.
        rgb *= (1+.09*pores)[:,:,None]
        upper = np.maximum(0,np.sin(2*pi*u))
        margin = smooth(.925,.997,v)*(.39+.56*upper)
        edge = np.array([.115,.285,.032])+upper[:,:,None]*np.array([.21,.24,.085])
        rgb = rgb*(1-margin[:,:,None])+edge*margin[:,:,None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
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
        y = BODY_Y_RANGE[0]+u*(BODY_Y_RANGE[1]-BODY_Y_RANGE[0])
        side_angle = np.arcsin(dorsal)
        radius = naris_radius(y,side_angle)
        aperture = .94*(1-smooth(.40,1.07,radius))
        lip = .22*np.maximum(0,1-((radius-1.12)/.35)**2)**2
        rgb = rgb*(1-lip[:,:,None])+np.array([.26,.45,.09])*lip[:,:,None]
        rgb = rgb*(1-aperture[:,:,None])+np.array([.005,.012,.003])*aperture[:,:,None]
        ear_radius = tympanic_radius(y,side_angle)
        ear = 1-smooth(.68,1.06,ear_radius)
        ear_rim = np.maximum(0,1-((ear_radius-1.02)/.26)**2)**2
        rgb *= (1-.23*ear+.045*ear_rim)[:,:,None]
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
        roughness += .04*ear[:,:,None]
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
        jaw_color = painted_maps('Original lower jaw', 512, 256, 'jaw')[0]
        self.jaw_skin = material('Lower lip and chin skin', (.50,.49,.31), .48,
                                  maps=(jaw_color, limb_maps[1], limb_maps[2]), coat=.035)
        oral_color = painted_maps('Original oral floor', 384, 192, 'oral floor')[0]
        self.oral = material('Warm oral mucosa', (.32, .131, .119), .53,
                             maps=(oral_color, None, None), coat=.045)
        self.oral_dark = material('Recessed oral tissue', (.055, .025, .023), .53)
        tongue_color = painted_maps('Original tongue', 512, 256, 'tongue')[0]
        self.pink = material('Tongue muscle', (.40, .16, .139), .45,
                             maps=(tongue_color, None, None), coat=.10)
        self.dark = material('Mouth seam', (.006, .011, .004), .5)
        self.iris = material('Original red iris and vertical pupil', (.7, .07, .01), .205,
                             maps=painted_maps('Original iris', 1024, 1024, 'iris'), coat=.24)
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
            brow *= 1-.19*float(smooth(-.069,-.055,y)*(1-smooth(-.039,-.024,y)))
            z += brow*float(smooth(0,.22,s))*(1-float(smooth(-.030,-.012,y)))
            if -.069 < y < -.022:
                # Broaden the crown between the brows, with a gentler slope
                # down to the nasal bridge and a quick roll into the cheeks.
                forehead = s**4.1*float(smooth(.35,.67,s))
                taper = smooth(-.069,-.050,y)*(1-smooth(-.039,-.022,y))
                z += .00390*forehead*taper
            # The canthus follows the edge between the upper snout and cheek.
            # A shallow falloff on its outer side defines that change of plane.
            if -.080 < y < -.045:
                along = float(smooth(-.076,-.052,y))
                offset = abs(x)-width*(.62+.14*along)
                envelope = float(smooth(-.080,-.074,y)*(1-smooth(-.055,-.045,y)))
                crest = .00165*exp(-(offset/.0034)**2)
                flank = .00075*exp(-((offset-.0054)/.0036)**2)
                z += envelope*(crest-flank)*s**.4
            if -.082 < y < -.063:
                rise = smooth(-.082,-.075,y)*(1-smooth(-.071,-.063,y))
                z += .00115*rise*float(smooth(.64,.98,s))
            # Both nares are sculpted into the same surface as the muzzle.
            if abs(y-NARIS_Y) < .0022:
                radius = naris_radius(y,acos(ratio))
                basin = .00074*max(0,1-(radius/1.04)**2)**2
                rim = .00022*max(0,1-((radius-1.11)/.40)**2)**2
                z += (rim-basin)*s**.4
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
        near_nares = abs(midpoints-NARIS_Y) < .004
        near_tip = midpoints < controls[0,0]+.005
        near_orbits = (midpoints > -.065) & (midpoints < -.035)
        near_ears = (midpoints > -.043) & (midpoints < -.028)
        rows = np.sort(np.concatenate((base_y,midpoints[near_nares | near_tip | near_orbits | near_ears])))
        nasal_rows = (rows[:-1]+rows[1:])*.5
        rows = np.sort(np.concatenate((rows,nasal_rows[abs(nasal_rows-NARIS_Y)<.0018])))
        base_angles = np.linspace(0,2*pi,97)
        angle_midpoints = (base_angles[:-1]+base_angles[1:])*.5
        cheek_angle = np.arctan2(np.sin(angle_midpoints),np.abs(np.cos(angle_midpoints)))
        cheek = (cheek_angle>.07) & (cheek_angle<.79)
        angles = np.sort(np.concatenate((base_angles,angle_midpoints[cheek])))
        nasal_angles = (angles[:-1]+angles[1:])*.5
        nasal_side_angles = np.arcsin(np.sin(nasal_angles))
        angles = np.sort(np.concatenate((angles,nasal_angles[abs(nasal_side_angles-NARIS_ANGLE)<.14])))
        rings, segments = len(rows)-1, len(angles)-1
        centers = [(sign,self.bones['FX_eye.'+side][0]) for side,sign in [('L',-1),('R',1)]]
        for y in rows:
            u = (y-controls[0,0])/(controls[-1,0]-controls[0,0])
            section = self.section_at(y)
            width, bottom, top = section[1:]
            torso = float(smooth(-.022,-.011,y))
            chest = torso*exp(-((y+.002)/.016)**2)
            waist = torso*exp(-((y-.021)/.014)**2)
            pelvis = torso*exp(-((y-.045)/.016)**2)
            taper = .0095*float(smooth(.043,.073,y))
            for theta in angles:
                x = width*cos(theta)
                arc = sin(theta)
                z = self.body_height(x, y, arc>=0, section)
                point = orbital_recess((x,y,z),centers)
                point.x += tympanic_relief(y,theta)
                if torso:
                    # Broaden the haunches and round the belly between the
                    # shoulders and hips. Shorten the free rump behind them.
                    point.x *= 1+.040*chest-.042*waist+.112*pelvis
                    point.y -= taper
                    point.z += (.00145*chest+.00118*pelvis)*max(0,arc)**1.6
                    point.z -= (.00165*waist+.00065*pelvis)*max(0,-arc)**1.4
                vertices.append(point);uv.append((u,theta/(2*pi)))
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
                shift = Vector((sign*.0021,0,.0013))
                point += shift*roll
                tangent += shift*(-4*(value-2)/.20**2*roll)
            tangent.normalize();axis = tangent.cross(Vector((0, 0, 1)))
            if axis.length < .01:axis = tangent.cross(Vector((0, 1, 0)))
            axis.normalize();up = tangent.cross(axis).normalized()
            if up.z < 0:up = -up;axis = -axis
            radius = radii[span]*(1-t)+radii[span+1]*t
            if bulges:
                swell = sin(pi*t)**2
                if attachment:
                    swell *= 1+.90*(.5-t)
                radius *= 1+bulges[span]*swell
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
                    radial *= 1+.19*np.exp(-((value-2)/.18)**2)
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
            chin = .0010*smooth(-.083,-.077,y)*(1-smooth(-.059,-.047,y))
            side_inset = .00064*smooth(-.082,-.072,y)*(1-smooth(-.054,-.046,y))
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
                    ridge, _ = oral_floor_folds(u, s)
                    z = surface+.00030*sqrt(s)+(oral_taper*(bowl+rim)+.00032*ridge)*sqrt(s)
                else:
                    underside = -s
                    lateral_roll = sin(pi*underside)**2
                    z = surface-(.00025+depth+chin*underside)*sqrt(underside)-throat_join*lateral_roll
                    x -= side_inset*lateral_roll*cos(angle)
                # Seat the lip rim inside the curved nose at rest.
                z += inset*exp(-(s/.63)**2)
                vertices.append((x, y+.80*inset, z));uv.append((u, j/segments))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1
                faces.append((a, b, b+1, a+1));inside.append(sin((j+.5)/segments*2*pi)>.28)
        faces.extend([tuple(reversed(range(segments))), tuple(rings*(segments+1)+j for j in range(segments))])
        obj = self.mesh('Articulated jaw and recessed oral floor', vertices, faces, uv,
                        [{'FX-jaw':1} for _ in vertices], self.jaw_skin)
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
            [-.0565,.00470, .00010,.00132],
            [-.0500,.00423, .00020,.00131],
            [-.0470,.00538, .00006,.00149],
            [-.0430,.00705, .00008,.00158],
            [-.0395,.00666, .00007,.00127],
            [-.0366,.00416,-.00002,.00087],
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
                radii = [.00545,.00375,.00248,.00330]
                bulges = [.24,.51,0]
                flatten = [.88,.84,.70,.32]
                inset = .0095
            else:
                radii = [.00760,.00412,.00305,.00286,.00420]
                bulges = [.13,.57,.02,0]
                flatten = [.65,.70,.82,.64,.30]
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
        self.arm['model_revision'] = 'original-red-eye-v38'
        self.arm['forward_axis'] = 'Blender -Y, glTF +Z'
        return self
