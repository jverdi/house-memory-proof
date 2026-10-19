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


def taper_fixture(rectangular=False):
    source=str(uuid.uuid4());route=[dict(x=0,y=0,z=0),dict(x=1,y=0,z=0)]
    value=dict(version=3,sourceFeatureID=source,sourceRevision=1,sourceInterval=0,
               section='Rectangular' if rectangular else 'Round',widthMetres=.2 if rectangular else .05,
               endWidthMetres=.08 if rectangular else .09,evidence='Measured endpoints and checked straight linear transition',recorded=0)
    if rectangular:value.update(heightMetres=.1,endHeightMetres=.16,widthAxis=dict(x=0,y=1,z=0))
    n=4 if rectangular else 64;vertices=[];triangles=[]
    for end in [0,1]:
        if rectangular:
            w,h=(.2,.1) if end==0 else (.08,.16)
            vertices += [dict(x=end,y=y*w/2,z=z*h/2) for y,z in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        else:
            radius=.025 if end==0 else .045
            vertices += [dict(x=end,y=-radius*math.sin(2*math.pi*i/n),z=radius*math.cos(2*math.pi*i/n)) for i in range(n)]
    vertices += copy.deepcopy(route)
    for i in range(n):j=(i+1)%n;triangles += [i,j,i+n,j,j+n,i+n,2*n,j,i,2*n+1,i+n,j+n]
    return dict(id=str(uuid.uuid4()),kind='synthetic',route=route,mesh=dict(vertices=vertices,triangles=triangles),
                annotationSources=[dict(featureID=source,revision=1)],envelope=value)


class TaperedEnvelopeReader(unittest.TestCase):
    def test_analytic_round_and_rectangular_endpoint_geometry(self):
        for rectangular in [False,True]:
            feature=taper_fixture(rectangular);envelope_check(feature['envelope'],feature)
            for mutate in [lambda f:f['mesh']['vertices'][-3].update(x=.99),
                           lambda f:f['mesh']['vertices'][-1].update(z=.01),
                           lambda f:f['mesh']['triangles'].__setitem__(0,2),
                           lambda f:f['envelope'].update(endWidthMetres=.1),
                           lambda f:f['route'][0].update(x=.1)]:
                bad=copy.deepcopy(feature);mutate(bad)
                with self.assertRaises(InvalidPackage):envelope_check(bad['envelope'],bad)

    def test_incomplete_mixed_or_invalid_dimensions_are_refused(self):
        for rectangular in [False,True]:
            feature=taper_fixture(rectangular)
            faults=[dict(endWidthMetres=None),dict(endWidthMetres=0),dict(endWidthMetres=True),
                    dict(endWidthMetres=float('nan')),dict(endWidthMetres=4.1),dict(sourceEndInterval=1),
                    dict(version=1),dict(version=2),dict(endWidthMetres=.001,dimensionToleranceMetres=.001),
                    dict(endHeightMetres=None if rectangular else .1)]
            for fields in faults:
                with self.subTest(rectangular=rectangular,fields=fields):
                    value=copy.deepcopy(feature['envelope']);value.update(fields)
                    with self.assertRaises(InvalidPackage):envelope_check(value)

    def test_csv_dates_and_endpoint_sizes_remain_explicit(self):
        value=taper_fixture(True)['envelope'];value['recorded']='2026-10-19T00:00:00Z'
        envelope_check(value,iso_dates=True)
        value['endHeightMetres']=None
        with self.assertRaises(InvalidPackage):envelope_check(value,iso_dates=True)


if __name__=='__main__':unittest.main()
