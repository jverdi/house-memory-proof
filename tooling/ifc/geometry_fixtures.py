"""Generate private analytic IFC geometry cases for both pinned native runtimes."""
import json
from pathlib import Path
import sys


def cases():
    base=(Path(__file__).resolve().parents[2]/'fixtures/block.ifc').read_text().replace('IFC2X3','IFC4').replace('.ELEMENT.','.NOTDEFINED.')
    def insert(source,rows):return source.replace('ENDSEC;\nEND-ISO',rows+'\nENDSEC;\nEND-ISO')
    metadata="""#70=IFCMATERIAL('Synthetic copper','Documentary material','Metal');
#71=IFCRELASSOCIATESMATERIAL('0J$yPqHBD2TuLf$X2etp$7',#5,$,$,(#22),#70);
#72=IFCBUILDINGELEMENTPROXYTYPE('1J$yPqHBD2TuLf$X2etp$8',#5,'Synthetic component type',$,$,$,$,$,'Analytic type',.NOTDEFINED.);
#73=IFCRELDEFINESBYTYPE('2J$yPqHBD2TuLf$X2etp$9',#5,$,$,(#22),#72);"""
    base=insert(base,metadata)
    nested=insert(base.replace('#15=IFCLOCALPLACEMENT($,#9);','#15=IFCLOCALPLACEMENT(#33,#35);'),"""#30=IFCCARTESIANPOINT((10.,20.,30.));
#31=IFCDIRECTION((0.,1.,0.));
#32=IFCAXIS2PLACEMENT3D(#30,#7,#31);
#33=IFCLOCALPLACEMENT($,#32);
#34=IFCCARTESIANPOINT((1.,0.,0.));
#35=IFCAXIS2PLACEMENT3D(#34,#7,#8);""")
    def mapped(operator):
        return insert(base.replace('#21=IFCPRODUCTDEFINITIONSHAPE($,$,(#20));','#21=IFCPRODUCTDEFINITIONSHAPE($,$,(#44));'),"""#30=IFCDIRECTION((0.,1.,0.));
#31=IFCDIRECTION((-1.,0.,0.));
#40=IFCCARTESIANPOINT((5.,0.,0.));
#41=IFCREPRESENTATIONMAP(#9,#20);
#42="""+operator+""";
#43=IFCMAPPEDITEM(#41,#42);
#44=IFCSHAPEREPRESENTATION(#10,'Body','MappedRepresentation',(#43));""")
    uniform=mapped('IFCCARTESIANTRANSFORMATIONOPERATOR3D(#30,#31,#40,2.,#7)')
    nonuniform=mapped('IFCCARTESIANTRANSFORMATIONOPERATOR3DNONUNIFORM(#30,#31,#40,2.,#7,3.,4.)')
    voided=insert(base,"""#50=IFCRECTANGLEPROFILEDEF(.AREA.,$,#17,0.5,3.);
#51=IFCEXTRUDEDAREASOLID(#50,#9,#7,2.);
#52=IFCSHAPEREPRESENTATION(#10,'Body','SweptSolid',(#51));
#53=IFCPRODUCTDEFINITIONSHAPE($,$,(#52));
#54=IFCOPENINGELEMENT('3J$yPqHBD2TuLf$X2etp$6',#5,'Synthetic opening',$,$,#15,#53,$,.OPENING.);
#55=IFCRELVOIDSELEMENT('0J$yPqHBD2TuLf$X2etp$5',#5,$,$,#22,#54);""")
    return [dict(name=name,source=source,low=low,high=high,volume=volume,products=products,converted=1)
        for name,source,low,high,volume,products in [
            ('nested placement',nested,[9,20.5,30],[11,21.5,33],6,1),
            ('mapped rotation and scale',uniform,[3,-1,0],[7,1,6],48,1),
            ('mapped nonuniform scale',nonuniform,[2,-1,0],[8,1,12],144,1),
            ('opening subtraction',voided,[-.5,-1,0],[.5,1,3],4,2)]]


if __name__=='__main__':
    target=Path(sys.argv[1]);target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(cases(),indent=2)+'\n')
