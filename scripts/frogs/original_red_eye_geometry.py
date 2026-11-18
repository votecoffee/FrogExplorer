"""Original red-eyed leaf-frog surfaces, rig and painted textures. MIT.

All coordinates, topology and pixels are generated here. No downloaded mesh,
rig, animation or photograph is read by this module. Coordinates are metres,
Blender Z up / -Y forward. The reference links are documented separately.
"""
from math import cos, sin, pi, sqrt
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from original_red_eye_feet import adhesive_pad, digital_web

EYE_RADIUS = .0136
EYE_ASPECT = (.91, 1.04, .90)


def eye_frame(sign):
    n = Vector((sign*.78, -.60, .16)).normalized()
    u = n.cross(Vector((0, 0, 1))).normalized()
    return n, u, u.cross(n).normalized()


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
        fiber = np.sin(angle*103+radius*27+grain*8)*.5
        fiber += np.sin(angle*189-radius*49+grain*3)*.25
        crypts = value_noise(u, v, 220, 220, 216)
        gold = smooth(.15, .68, fiber+crypts*.35)*(1-smooth(.72, 1.0, radius))
        rgb = np.stack([.74+.10*fiber+.09*(1-radius)+.08*crypts,
                        .095+.09*(1-radius)+.065*fiber+.11*gold,
                        .018+.012*fiber], axis=-1)
        pupil_width = .17*np.maximum(0, 1-(y/.73)**2)**.65
        pupil = (abs(x) < pupil_width) & (abs(y) < .73)
        rgb[pupil] = [.006, .008, .006]
        rim = smooth(.94, .995, radius)
        rgb = rgb*(1-rim[:, :, None])+np.array([.045, .025, .008])*rim[:, :, None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    if kind == 'ventral':
        rgb = np.broadcast_to([.74, .77, .59], (height, width, 3)).copy()
        rgb *= (1+.035*grain+.018*pores)[:, :, None]
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
    else:
        blue = smooth(-.7, -.35, dorsal)*(1-smooth(.05, .35, dorsal))
        blue *= .30+.40*(1-smooth(.25, .90, u))
        rgb = rgb*(1-blue[:, :, None])+np.array([.045, .19, .39])*blue[:, :, None]
    du, dv = np.gradient(pores)
    normals = np.stack([.5-du*.25, .5-dv*.25, np.ones_like(u)], axis=-1)
    roughness = np.repeat((.40+.06*grain+.02*pores)[:, :, None], 3, axis=2)
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
        self.oral = material('Warm oral mucosa', (.32, .19, .17), .43, coat=.12)
        self.oral_dark = material('Recessed oral tissue', (.055, .025, .023), .53)
        self.pink = material('Tongue muscle', (.48, .19, .16), .39, coat=.16)
        self.dark = material('Mouth seam and nares', (.028, .05, .012), .5)
        self.iris = material('Original red iris and vertical pupil', (.7, .07, .01), .13,
                             maps=painted_maps('Original iris', 1024, 1024, 'iris'), coat=.7)
        arm_data = bpy.data.armatures.new('Original leaf-frog joint definitions')
        self.arm = bpy.data.objects.new('Original_Red_Eye_Rig', arm_data)
        bpy.context.collection.objects.link(self.arm)
        bpy.context.view_layer.objects.active = self.arm;self.arm.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        self.bone('root', (0, 0, 0), (0, 0, .015))
        self.bone('DEF-spine.003', (0, .025, .042), (0, -.022, .054), 'root')
        self.bone('Head', (0, -.022, .054), (0, -.069, .057), 'DEF-spine.003')
        self.bone('FX-jaw', (0, -.024, .037), (0, -.072, .037), 'Head')
        self.bone('Throat', (0, -.025, .036), (0, -.045, .033), 'FX-jaw')
        self.bone('Tongue', (0, -.068, .039), (0, -.049, .040), 'FX-jaw')
        self.bone('TongueTip', (0, -.049, .040), (0, -.039, .041), 'Tongue')
        for side, sign in [('L', -1), ('R', 1)]:
            shoulder = Vector((sign*.031, -.022, .048))
            elbow = Vector((sign*.058, .001, .024))
            wrist = Vector((sign*.068, -.056, .007))
            hand = Vector((sign*.070, -.065, .005))
            hip = Vector((sign*.025, .044, .042))
            knee = Vector((sign*.060, .010, .027))
            ankle = Vector((sign*.059, .073, .013))
            heel = Vector((sign*.047, .028, .006))
            foot = Vector((sign*.052, .009, .005))
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
                ('hand', hand, 'DEF-hand.'+side, [.021, .029, .030, .023]),
                ('foot', foot, 'DEF-foot.'+side, [.020, .028, .036, .033, .024])]:
                digits = []
                for i, length in enumerate(lengths):
                    fan = (i-(len(lengths)-1)/2)*.43
                    base = palm+Vector((sign*(i-(len(lengths)-1)/2)*.0028, -.002, 0))
                    end = base+Vector((sign*sin(fan)*length, -cos(fan)*length, -.0003))
                    middle = base.lerp(end, .55)+Vector((0, 0, .0016))
                    name = f'Digit_{label}_{i+1}.{side}'
                    self.bone(name, base, middle, parent)
                    self.bone(name+'_tip', middle, end, name)
                    digits.append(([base, middle, end], [name, name+'_tip']))
                self.digits[(side, label)] = digits
            center = Vector((sign*.0335, -.051, .070))
            self.bone('FX_eye.'+side, center, center+Vector((0, -.01, 0)), 'Head')
            self.bone('Lid.'+side, center, center+Vector((0, 0, .01)), 'Head')
        bpy.ops.object.mode_set(mode='OBJECT')
        self.rest = {bone.name:bone.matrix_local.to_quaternion() for bone in arm_data.bones}

    def bone(self, name, head, tail, parent=None):
        bone = self.arm.data.edit_bones.new(name);bone.head = head;bone.tail = tail
        if parent:bone.parent = self.arm.data.edit_bones[parent]
        self.bones[name] = (Vector(head), Vector(tail))

    def mesh(self, name, vertices, faces, uv, weights, mat):
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

    def body_height(self, x, y, upper=True, section=None):
        section = profile(self.body_sections, y) if section is None else section
        width, bottom, top = section[1:]
        s = sqrt(max(0, 1-(x/width)**2))*(1 if upper else -1)
        z = (top+bottom)/2+(top-bottom)/2*s
        if not upper:
            flat = bottom+(top-bottom)/2*(1-(-s)**.30)
            blend = float(1-smooth(-.032, -.012, y))
            z = z*(1-blend)+flat*blend
        else:z += .0125*np.exp(-((abs(x)-.029)/.011)**2-((y+.039)/.019)**2)*s**.8
        return float(z)

    def body(self):
        # Smooth longitudinal sections include the head: there is no neck seam.
        controls = np.array([
            [-.083, .0003, .043, .044], [-.078, .021, .0415, .059],
            [-.069, .034, .039, .067], [-.049, .0405, .0375, .073],
            [-.030, .0355, .038, .070], [-.008, .0305, .025, .065],
            [.020, .0275, .022, .059], [.047, .0245, .023, .0555],
            [.060, .019, .026, .051], [.070, .012, .029, .044],
            [.074, .0055, .033, .039], [.075, .0001, .0355, .0355]])
        self.body_sections = controls
        vertices = [];faces = [];uv = [];weights = []
        rings, segments = 96, 96
        for i in range(rings+1):
            u = i/rings;y = controls[0, 0]+u*(controls[-1, 0]-controls[0, 0])
            section = profile(controls, y)
            width, bottom, top = section[1:]
            for j in range(segments+1):
                theta = 2*pi*j/segments;x = width*cos(theta)
                z = self.body_height(x, y, sin(theta)>=0, section)
                vertices.append((x, y, z));uv.append((u, j/segments))
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
                    radial *= 1-.08*np.exp(-((value-2)/.12)**2)*max(0,sin(angle))
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

    def jaw(self):
        sections = np.array([[-.082, .0002, .042], [-.078, .019, .041],
                             [-.069, .0315, .039], [-.049, .0355, .037],
                             [-.029, .032, .037], [-.023, .0002, .037]])
        self.jaw_sections = sections
        vertices = [];faces = [];uv = [];inside = []
        rings, segments = 48, 64
        for i in range(rings+1):
            y = sections[0, 0]+i/rings*(sections[-1, 0]-sections[0, 0])
            _, width, center = profile(sections, y)
            rim = self.body_height(width, y, False)-.00020
            floor = self.body_height(0, y, False)-.0007
            chin = floor-(.0016+.0007*sin(pi*i/rings))
            for j in range(segments+1):
                angle = j/segments*2*pi;s = sin(angle)
                z = rim-(rim-floor)*s**.75 if s>=0 else rim-.0010-(rim-.0010-chin)*(-s)**.65
                vertices.append((width*cos(angle), y, z));uv.append((i/rings, j/segments))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1
                faces.append((a, b, b+1, a+1));inside.append(sin((j+.5)/segments*2*pi)>.40)
        faces.extend([tuple(reversed(range(segments))), tuple(rings*(segments+1)+j for j in range(segments))])
        obj = self.mesh('Articulated jaw and recessed oral floor', vertices, faces, uv,
                        [{'FX-jaw':1} for _ in vertices], self.cream)
        obj.data.materials.append(self.oral)
        for polygon, oral in zip(obj.data.polygons, inside):polygon.material_index = 1 if oral else 0

    def palate(self):
        vertices = [];faces = [];uv = []
        rings, segments = 20, 64
        for i in range(rings+1):
            r = i/rings
            for j in range(segments+1):
                angle = 2*pi*j/segments;x = .030*r*cos(angle);y = -.051+.023*r*sin(angle)
                vertices.append((x, y, self.body_height(x, y, False)-.0003))
                uv.append((.5+.5*r*cos(angle), .5+.5*r*sin(angle)))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1;faces.append((a, a+1, b+1, b))
        self.mesh('Recessed curved palate', vertices, faces, uv, [{'Head':1} for _ in vertices], self.oral)
        for sign in [-1, 1]:
            line = []
            for t in np.linspace(0, 1, 20):
                x = sign*(.014+.003*sin(pi*t));y = -.065+.030*t
                line.append((x, y, self.body_height(x, y, False)-.00055))
            self.tube('Soft palatal fold '+str(sign), line, [.00032]*len(line), ['Head']*(len(line)-1), self.oral, 1, 8)

    def features(self):
        self.jaw()
        self.palate()
        self.ellipsoid('Dark rear oral cavity', (0, -.027, .0355), (.026, .002, .004), self.oral_dark, 'Head')
        self.ellipsoid('Gular breathing sac', (0, -.031, .0325), (.023, .022, .004), self.cream, 'Throat', 18, 36)
        self.ellipsoid('Tongue folded muscle', (0, -.056, self.body_height(0, -.056, False)+.0011), (.009, .012, .0018), self.pink, 'Tongue')
        self.ellipsoid('Tongue rounded tip', (0, -.044, self.body_height(0, -.044, False)+.0011), (.010, .007, .0018), self.pink, 'TongueTip')
        for side, sign in [('L', -1), ('R', 1)]:
            center = self.bones['FX_eye.'+side][0];n, u, v = eye_frame(sign)
            # A fitted back shell meets the corneal aperture. A separate round
            # sphere leaves gaps and exposes the back of the iris in profile.
            self.cap('Green orbital socket '+side, center, -n, .0139, pi-1.25,
                     self.orbit_mat, 'Head', 24, 48, aspect=EYE_ASPECT, disk_uv=False)
            self.cap('Red corneal surface '+side, center, n, EYE_RADIUS, 1.36, self.iris, 'FX_eye.'+side, aspect=EYE_ASPECT)
            # The cap retracts above and behind the iris, then closes over it.
            lid_axis = (Vector((0, 0, 1))*.55-n*.90).normalized()
            self.cap('Mobile upper eyelid '+side, center, lid_axis, .0141, 1.30, self.orbit_mat, 'Lid.'+side, 20, 48, aspect=EYE_ASPECT)
            ring = [center+n*(.0137*cos(1.36)*EYE_ASPECT[2])+(u*(cos(a)*EYE_ASPECT[0])+v*(sin(a)*EYE_ASPECT[1]))*(.0137*sin(1.36)) for a in np.linspace(0, 2*pi, 65)]
            self.tube('Fine eye rim '+side, ring, [.00025]*len(ring), ['Head']*(len(ring)-1), self.cream, 1, 8)
            lip = []
            for y in np.linspace(-.0819, -.029, 36):
                x = sign*float(profile(self.jaw_sections, y)[1])
                lip.append((x, y, self.body_height(x, y, False)-.00005))
            self.tube('Mouth commissure '+side, lip, [.00028]*len(lip), ['Head']*(len(lip)-1), self.dark, 1, 8)
            x, y = sign*.018, -.071
            z = self.body_height(x, y)
            self.ellipsoid('Nostril '+side, (x, y, z+.00005), (.0010, .00065, .00018), self.dark, 'Head', 8, 16)

    def limbs_and_digits(self):
        for (side, label), (points, bones) in self.limbs.items():
            if label == 'arm':
                radii = [.0068, .0046, .0030, .0036];bulges = [.16, .14, .0];flatten = [.84,.78,.65,.32]
                inset = .0065
            else:
                radii = [.0120, .0058, .0035, .0032, .0046];bulges = [.40, .24, .08, .0];flatten = [.91,.82,.76,.60,.30]
                inset = .0100
            self.tube('Continuous '+label+' '+side, points, radii, bones, self.limb_mat, 12, 24, bulges, flatten, True,
                      (-1 if side=='L' else 1, inset))
            palm = points[-1]
            self.ellipsoid('Orange '+label+' palm '+side, palm+Vector((0,0,.00025)), (.0067, .0061, .00165), self.orange, bones[-1])
        for (side, label), digits in self.digits.items():
            sizes = [.84,1.0,1.03,.91] if label=='hand' else [.80,.93,1.06,1.0,.88]
            for number, (points, bones) in enumerate(digits, 1):
                size = sizes[number-1]
                self.tube(f'{label} digit {number} {side}', points, [r*size for r in [.00165,.00135,.00160]], bones, self.orange, 10, 16, [.16,.12], [.88,.84,.65], True)
                adhesive_pad(self, f'{label} adhesive disc {number} {side}', points, bones[-1], size)
            digital_web(self, side, label, digits)

    def build(self):
        self.body();self.limbs_and_digits();self.features()
        self.arm['provenance'] = 'Original parametric mesh, painted pixels, joint layout and motions; MIT. No imported model data.'
        self.arm['species'] = 'Agalychnis callidryas'
        self.arm['model_revision'] = 'original-red-eye-v4'
        self.arm['forward_axis'] = 'Blender -Y, glTF +Z'
        return self
