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
    if kind == 'iris':
        x, y = (u-.5)*2, (v-.5)*2
        radius = np.sqrt(x*x+y*y)
        angle = np.arctan2(y, x)
        fiber = np.sin(angle*103+radius*27+grain*8)*.5
        fiber += np.sin(angle*189-radius*49)*.25
        rgb = np.stack([.78+.11*fiber+.1*(1-radius),
                        .13+.12*(1-radius)+.06*fiber,
                        .025+.018*fiber], axis=-1)
        pupil_width = .17*np.maximum(0, 1-(y/.73)**2)**.65
        pupil = (abs(x) < pupil_width) & (abs(y) < .73)
        rgb[pupil] = [.006, .008, .006]
        rim = smooth(.88, .98, radius)
        rgb = rgb*(1-rim[:, :, None])+np.array([.055, .068, .024])*rim[:, :, None]
        return image(name+' color', np.clip(rgb, 0, 1)), None, None
    dorsal = np.sin(v*2*pi)
    green = np.array([.075, .40, .018]) if kind == 'body' else np.array([.07, .37, .016])
    rgb = np.broadcast_to(green, (height, width, 3)).copy()
    rgb *= (1+.09*grain+.045*pores)[:, :, None]
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
        rng = np.random.default_rng(801)
        for _ in range(24):
            a, b = rng.uniform(.25, .89), rng.uniform(.06, .43)
            fleck = np.exp(-((u-a)/.0022)**2-((v-b)/.0022)**2)*.65
            rgb = rgb*(1-fleck[:, :, None])+np.array([.85, .88, .58])*fleck[:, :, None]
    else:
        blue = smooth(-.5, -.15, dorsal)*(1-smooth(.0, .25, dorsal))*.50
        rgb = rgb*(1-blue[:, :, None])+np.array([.06, .29, .37])*blue[:, :, None]
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
        self.orbit_mat = material('Green orbital skin', (.075, .40, .018), maps=(None, limb_maps[1], limb_maps[2]))
        self.orange = material('Orange digital pads', (.78, .15, .018), .40,
                               maps=(None, limb_maps[1], limb_maps[2]), coat=.12)
        self.cream = material('Ivory granular throat', (.62, .65, .39), .48)
        self.oral = material('Warm oral mucosa', (.28, .055, .065), .42, coat=.3)
        self.pink = material('Tongue muscle', (.46, .095, .11), .35, coat=.25)
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
        self.bone('Throat', (0, -.025, .031), (0, -.045, .028), 'FX-jaw')
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
            center = Vector((sign*.032, -.048, .071))
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

    def ellipsoid(self, name, center, size, mat, bone, rings=14, segments=24):
        vertices = [];uv = [];faces = []
        for i in range(rings+1):
            phi = pi*i/rings
            for j in range(segments+1):
                theta = 2*pi*j/segments
                point = Vector((size[0]*sin(phi)*cos(theta), size[1]*sin(phi)*sin(theta), size[2]*cos(phi)))+Vector(center)
                vertices.append(point);uv.append((j/segments, i/rings))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1
                faces.append((a, b, b+1, a+1))
        return self.mesh(name, vertices, faces, uv, [{bone:1} for _ in vertices], mat)

    def body(self):
        # Smooth longitudinal sections include the head: there is no neck seam.
        controls = np.array([
            [-.081, .0003, .043, .044], [-.076, .025, .042, .057],
            [-.067, .0365, .039, .065], [-.049, .041, .036, .074],
            [-.030, .036, .030, .072], [-.008, .0315, .025, .066],
            [.020, .030, .022, .061], [.047, .026, .023, .062],
            [.060, .021, .026, .058], [.070, .013, .031, .051],
            [.074, .006, .036, .045], [.075, .0001, .040, .040]])
        vertices = [];faces = [];uv = [];weights = []
        rings, segments = 96, 96
        for i in range(rings+1):
            u = i/rings;y = controls[0, 0]+u*(controls[-1, 0]-controls[0, 0])
            index = min(len(controls)-2, max(0, int(np.searchsorted(controls[:, 0], y)-1)))
            t = (y-controls[index, 0])/(controls[index+1, 0]-controls[index, 0])
            p0, p1 = controls[max(0, index-1)], controls[index]
            p2, p3 = controls[index+1], controls[min(len(controls)-1, index+2)]
            section = .5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
            width, bottom, top = section[1:]
            for j in range(segments+1):
                theta = 2*pi*j/segments;x = width*cos(theta)
                z = (top+bottom)/2+(top-bottom)/2*sin(theta)
                if sin(theta)<0:
                    flat = bottom+(top-bottom)/2*(1-(-sin(theta))**.30)
                    blend = float(1-smooth(-.032, -.012, y))
                    z = z*(1-blend)+flat*blend
                # Integrated supraorbital swell, with a low, rounded muzzle.
                z += .006*np.exp(-((abs(x)-.030)/.012)**2-((y+.047)/.018)**2)*max(0, sin(theta))**2
                vertices.append((x, y, z));uv.append((u, j/segments))
                head = float(1-smooth(-.038, -.015, y))
                weights.append({'Head':head, 'DEF-spine.003':1-head})
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1
                faces.append((a, b, b+1, a+1))
        faces.extend([tuple(reversed(range(segments))), tuple(rings*(segments+1)+j for j in range(segments))])
        return self.mesh('Original continuous trunk and muzzle', vertices, faces, uv, weights, self.body_mat)

    def tube(self, name, points, radii, bones, mat, rings_per_span=8, segments=18):
        points = [Vector(p) for p in points]
        vertices = [];uv = [];weights = [];faces = []
        total = (len(points)-1)*rings_per_span
        for ring in range(total+1):
            value = ring/rings_per_span;span = min(len(points)-2, int(value));t = value-span
            p0 = points[max(0, span-1)];p1 = points[span];p2 = points[span+1];p3 = points[min(len(points)-1, span+2)]
            point = .5*(2*p1+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
            tangent = (-p0+p2)+(2*p0-5*p1+4*p2-p3)*(2*t)+(-p0+3*p1-3*p2+p3)*(3*t*t)
            tangent.normalize();axis = tangent.cross(Vector((0, 0, 1)))
            if axis.length < .01:axis = tangent.cross(Vector((0, 1, 0)))
            axis.normalize();up = tangent.cross(axis).normalized()
            if up.z < 0:up = -up;axis = -axis
            radius = radii[span]*(1-t)+radii[span+1]*t
            if span == 0:radius *= .75+.25*sin(min(1, t*3)*pi/2)
            current = min(span, len(bones)-1)
            skin = {bones[current]:1.0}
            if span > 0 and t < .25 and bones[current] != bones[current-1]:
                mix = .5*(1-t/.25);skin = {bones[current]:1-mix, bones[current-1]:mix}
            elif current+1 < len(bones) and t > .75 and bones[current] != bones[current+1]:
                mix = .5*(t-.75)/.25;skin = {bones[current]:1-mix, bones[current+1]:mix}
            for j in range(segments+1):
                angle = 2*pi*j/segments
                vertices.append(point+axis*(cos(angle)*radius)+up*(sin(angle)*radius*.91))
                uv.append((ring/total, j/segments));weights.append(skin)
        for i in range(total):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1;faces.append((a, a+1, b+1, b))
        faces.extend([tuple(reversed(range(segments))), tuple(total*(segments+1)+j for j in range(segments))])
        return self.mesh(name, vertices, faces, uv, weights, mat)

    def cap(self, name, center, direction, radius, angle, mat, bone, rings=20, segments=64):
        n = Vector(direction).normalized();u = n.cross(Vector((0, 0, 1))).normalized();v = u.cross(n).normalized()
        vertices = [];uv = [];faces = []
        for i in range(rings+1):
            phi = angle*i/rings
            for j in range(segments+1):
                theta = 2*pi*j/segments
                radial = u*cos(theta)+v*sin(theta)
                vertices.append(Vector(center)+radius*(n*cos(phi)+radial*sin(phi)))
                fraction = sin(phi)/sin(angle)
                uv.append((.5+.5*fraction*cos(theta), .5+.5*fraction*sin(theta)))
        for i in range(rings):
            for j in range(segments):
                a = i*(segments+1)+j;b = a+segments+1;faces.append((a, a+1, b+1, b))
        return self.mesh(name, vertices, faces, uv, [{bone:1} for _ in vertices], mat)

    def jaw(self):
        sections = np.array([[-.080, .0002, .042], [-.076, .024, .041],
                             [-.067, .034, .039], [-.049, .037, .037],
                             [-.029, .033, .037], [-.023, .0002, .037]])
        vertices = [];faces = [];uv = [];inside = []
        rings, segments = 48, 64
        for i in range(rings+1):
            y = sections[0, 0]+i/rings*(sections[-1, 0]-sections[0, 0])
            width = float(np.interp(y, sections[:, 0], sections[:, 1]))
            center = float(np.interp(y, sections[:, 0], sections[:, 2]))
            for j in range(segments+1):
                angle = j/segments*2*pi;s = sin(angle)
                z = center+(.0015-.003*s**.8 if s>=0 else -.0015-.003*(-s)**.8)
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

    def features(self):
        self.jaw()
        self.ellipsoid('Upper palate', (0, -.050, .042), (.029, .023, .0010), self.oral, 'Head', 12, 48)
        self.ellipsoid('Dark rear oral cavity', (0, -.027, .038), (.028, .0018, .006), self.oral, 'Head')
        self.ellipsoid('Gular breathing sac', (0, -.035, .030), (.021, .022, .006), self.cream, 'Throat', 18, 36)
        self.ellipsoid('Tongue folded muscle', (0, -.056, .044), (.009, .012, .0018), self.pink, 'Tongue')
        self.ellipsoid('Tongue rounded tip', (0, -.044, .044), (.010, .007, .0018), self.pink, 'TongueTip')
        for side, sign in [('L', -1), ('R', 1)]:
            center = Vector((sign*.032, -.048, .071));n = Vector((sign*.63, -.69, .36)).normalized()
            self.ellipsoid('Green orbital socket '+side, center-n*.0025-Vector((0, 0, .0015)), (.014, .014, .0135), self.orbit_mat, 'Head', 22, 40)
            self.cap('Red corneal surface '+side, center, n, .0145, 1.36, self.iris, 'FX_eye.'+side)
            # The cap retracts above and behind the iris, then closes over it.
            lid_axis = (Vector((0, 0, 1))*.65-n*.76).normalized()
            self.cap('Mobile upper eyelid '+side, center, lid_axis, .01485, 1.05, self.orbit_mat, 'Lid.'+side, 16, 40)
            u = n.cross(Vector((0, 0, 1))).normalized();v = u.cross(n).normalized()
            ring = [center+n*(.0146*cos(1.36))+(u*cos(a)+v*sin(a))*(.0146*sin(1.36)) for a in np.linspace(0, 2*pi, 65)]
            self.tube('Fine eye rim '+side, ring, [.00032]*len(ring), ['Head']*(len(ring)-1), self.cream, 1, 8)
            lip = []
            for t in np.linspace(0, 1, 25):
                lip.append((sign*.036*sin(t*pi/2), -.080+.052*(1-cos(t*pi/2)), .042-.003*sin(t*pi/2)))
            self.tube('Mouth commissure '+side, lip, [.00045]*len(lip), ['Head']*(len(lip)-1), self.dark, 1, 8)
            self.ellipsoid('Nostril '+side, (sign*.019, -.071, .063), (.0015, .001, .0005), self.dark, 'Head', 8, 12)

    def limbs_and_digits(self):
        for (side, label), (points, bones) in self.limbs.items():
            if label == 'arm':radii = [.0082, .0062, .0035, .0040]
            else:radii = [.0130, .0090, .0066, .0039, .0048]
            self.tube('Continuous '+label+' '+side, points, radii, bones, self.limb_mat, 12, 24)
            palm = points[-1]
            self.ellipsoid('Orange '+label+' palm '+side, palm, (.0075, .007, .0025), self.orange, bones[-1])
        for (side, label), digits in self.digits.items():
            for number, (points, bones) in enumerate(digits, 1):
                self.tube(f'{label} digit {number} {side}', points, [.00165, .00135, .0016], bones, self.orange, 7, 12)
                self.ellipsoid(f'{label} adhesive disc {number} {side}', points[-1], (.0036, .0042, .00135), self.orange, bones[-1], 10, 20)
            palm = self.limbs[(side, 'arm' if label == 'hand' else 'leg')][0][-1]
            parent = 'DEF-'+label+'.'+side
            boundary = []
            for left, right in zip(digits[:-1], digits[1:]):
                a = left[0][0].lerp(left[0][-1], .43)
                b = right[0][0].lerp(right[0][-1], .43)
                for t in np.linspace(0, 1, 9):
                    point = a.lerp(b, float(t))
                    boundary.append(palm+(point-palm)*(1-.40*sin(pi*t)))
            verts = [palm+Vector((0, 0, -.0002)), *boundary]
            faces = [(0, i, i+1) for i in range(1, len(verts)-1)]
            self.mesh('Scalloped '+label+' webbing '+side, verts, faces,
                      [(p.x*30+.5, p.y*30+.5) for p in verts],
                      [{parent:1} for _ in verts], self.orange)

    def build(self):
        self.body();self.limbs_and_digits();self.features()
        self.arm['provenance'] = 'Original parametric mesh, painted pixels, joint layout and motions; MIT. No imported model data.'
        self.arm['species'] = 'Agalychnis callidryas'
        self.arm['forward_axis'] = 'Blender -Y, glTF +Z'
        return self
