import copy
import math
import unittest
import uuid
from package_check import envelope_check, InvalidPackage


def bent_fixture():
    # Analytic 90-degree elbow: both cylinders have a 25 mm outer radius.
    route=[dict(x=0,y=0,z=0),dict(x=1,y=0,z=0),dict(x=1,y=1,z=0)]
    vertices=[]
    for ring in range(3):
        for i in range(64):
            c=.025*math.cos(2*math.pi*i/64);s=.025*math.sin(2*math.pi*i/64)
            vertices.append([dict(x=0,y=-s,z=c),dict(x=1+s,y=-s,z=c),dict(x=1+s,y=1,z=c)][ring])
    vertices+=copy.deepcopy([route[0],route[-1]])
    triangles=[]
    for ring in range(2):
        for i in range(64):
            a=ring*64+i;b=ring*64+(i+1)%64;triangles += [a,b,a+64,b,b+64,a+64]
    for i in range(64):j=(i+1)%64;triangles += [192,j,i,193,128+i,128+j]
    source=str(uuid.uuid4())
    value=dict(version=2,sourceFeatureID=source,sourceRevision=1,sourceInterval=0,sourceEndInterval=1,
               section='Round',widthMetres=.05,evidence='Diameter measured along both recorded intervals',recorded=0)
    return dict(id=str(uuid.uuid4()),kind='synthetic',route=route,mesh=dict(vertices=vertices,triangles=triangles),
                annotationSources=[dict(featureID=source,revision=1)],envelope=value)


class ConnectedEnvelopeReader(unittest.TestCase):
    def test_analytic_joint_dimensions_caps_and_sampling(self):
        feature=bent_fixture();envelope_check(feature['envelope'],feature)
        mutations=[lambda f:f['envelope'].update(sourceEndInterval=2),lambda f:f['envelope'].update(version=1),
                   lambda f:f['envelope'].update(section='Rectangular'),lambda f:f['envelope'].update(widthMetres=.06),
                   lambda f:f['mesh']['vertices'][65].update(x=1),lambda f:f['mesh']['vertices'][-1].update(y=1.1),
                   lambda f:f['mesh']['triangles'].__setitem__(0,1),lambda f:f['route'][1].update(x=.001)]
        for i, mutate in enumerate(mutations):
            with self.subTest(fault=i):
                bad=copy.deepcopy(feature);mutate(bad)
                with self.assertRaises(InvalidPackage):envelope_check(bad['envelope'],bad)


if __name__=='__main__':unittest.main()
