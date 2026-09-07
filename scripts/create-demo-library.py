#!/usr/bin/env python3
"""Create an isolated, original example library for MakerDock screenshots (requires Pillow).
Never points at or reads an existing user library. Sample estimates are illustrative.
"""
import argparse, hashlib, io, json, math, uuid, zipfile
from pathlib import Path
from xml.sax.saxutils import escape
from PIL import Image, ImageDraw, ImageFilter

LOCALES = {
'en':(['Modular Desk Tray','Cable Comb Set','Spiral Pencil Cup','Everyday Phone Stand','Hex Planter','Filament Sample Tiles'],['Desk','Workshop','Home'],'MakerDock examples','A place for every small thing.','Fits perfectly. Printed in matte PLA.','0.20 mm · Standard'),
'ko':(['모듈형 데스크 트레이','케이블 정리 클립','나선형 연필꽂이','데일리 휴대폰 거치대','육각 화분','필라멘트 샘플 타일'],['책상','작업실','생활'],'MakerDock 예제','작은 물건도 제자리에.','크기가 딱 맞아요. 매트 PLA로 출력.','0.20 mm · 표준'),
'ja':(['モジュール式デスクトレー','ケーブル整理クリップ','スパイラルペンスタンド','スマートフォンスタンド','六角プランター','フィラメントサンプル'],['デスク','作業場','暮らし'],'MakerDock サンプル','小さな道具にも、決まった場所を。','ぴったりのサイズ。マットPLAで造形。','0.20 mm · 標準'),
'zh-Hans':(['模块化桌面收纳盘','线缆整理夹','螺旋笔筒','日常手机支架','六角花盆','耗材色板'],['桌面','工作室','家居'],'MakerDock 示例','每件小物，都有自己的位置。','尺寸刚好。使用哑光PLA打印。','0.20 mm · 标准')}
COLORS=['#3273EA','#F09B6F','#61BFA9','#8A7DCC','#DAAD55','#5BA9C9']

def box(x,y,z,w,d,h):
 v=[(x+i*w,y+j*d,z+k*h) for k in (0,1) for j in (0,1) for i in (0,1)]
 return [[v[i] for i in f] for f in [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]]
def tray(w=70,d=48,h=15,x=0,y=0):
 return box(x,y,0,w,d,3)+box(x,y,3,w,3,h)+box(x,y+d-3,3,w,3,h)+box(x,y+3,3,3,d-6,h)+box(x+w-3,y+3,3,3,d-6,h)
def cup(n=96,h=68,r=29,flute=2):
 rings=[]
 for z,inner in [(0,False),(h,False),(h,True),(3,True)]:
  ring=[]
  for i in range(n):
   a=2*math.pi*i/n;radius=r+(flute*math.cos(16*a-z*.10) if not inner else -3)
   ring.append((radius*math.cos(a),radius*math.sin(a),z))
  rings.append(ring)
 faces=[]
 for k in range(3):
  for i in range(n):faces.append([rings[k][i],rings[k][(i+1)%n],rings[k+1][(i+1)%n],rings[k+1][i]])
 faces += [list(reversed(rings[0])),rings[3]]
 return faces

def geometries():
 desk=tray()+box(35,3,3,3,42,15)
 comb=[]
 for j in range(3):
  comb+=box(j*26,0,0,20,50,4)
  for y in range(0,50,10):comb+=box(j*26,y,4,20,4,9)
 stand=box(0,0,0,50,55,5)+box(0,6,5,50,5,9)+box(4,38,5,42,7,48)+box(4,30,5,6,15,25)+box(40,30,5,6,15,25)
 tiles=[]
 for x,y in [(0,0),(30,0),(0,40),(30,40)]:tiles+=box(x,y,0,25,34,4)+box(x+3,y+3,4,19,8,2)
 return [desk,comb,cup(),stand,cup(n=6,h=47,r=34,flute=0),tiles]

def render(faces,color,plate=False):
 def proj(v):x,y,z=v;return ((x-y)*.866,(x+y)*.5-z)
 pts=[proj(v) for f in faces for v in f];lo=[min(v[i] for v in pts) for i in (0,1)];hi=[max(v[i] for v in pts) for i in (0,1)]
 scale=min(760/max(hi[0]-lo[0],1),510/max(hi[1]-lo[1],1));cx=(lo[0]+hi[0])/2;cy=(lo[1]+hi[1])/2
 im=Image.new('RGB',(1000,750),'#F2F5FA');shadow=Image.new('RGBA',im.size);sd=ImageDraw.Draw(shadow);sd.ellipse((180,585,820,660),fill=(33,48,70,30));im=Image.alpha_composite(im.convert('RGBA'),shadow.filter(ImageFilter.GaussianBlur(22)))
 draw=ImageDraw.Draw(im);rgb=tuple(bytes.fromhex(color[1:]));light=(-.3,-.5,.8)
 for f in sorted(faces,key=lambda f:sum(sum(v) for v in f)/len(f)):
  a,b,c=f[:3];u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)];norm=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]);length=math.sqrt(sum(q*q for q in norm)) or 1
  lum=.78+.23*abs(sum(norm[i]*light[i] for i in range(3))/length);fill=tuple(min(255,int(c*lum)) for c in rgb)
  polygon=[((proj(v)[0]-cx)*scale+500,(proj(v)[1]-cy)*scale+370) for v in f]
  draw.polygon(polygon,fill=fill)
 if plate:
  # A subtle build-plate border; the model itself remains the same mesh.
  draw.rounded_rectangle((30,30,970,720),radius=18,outline='#D7DFEA',width=3)
 out=io.BytesIO();im.convert('RGB').save(out,format='PNG',optimize=True);return out.getvalue()

def archive(title,faces,thumb):
 verts=[];tri=[]
 for face in faces:
  start=len(verts);verts+=face
  tri += [(start,start+i,start+i+1) for i in range(1,len(face)-1)]
 vs=''.join('<vertex x="%g" y="%g" z="%g"/>'%v for v in verts);ts=''.join('<triangle v1="%d" v2="%d" v3="%d"/>'%t for t in tri)
 xml=f'<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><metadata name="Title">{escape(title)}</metadata><metadata name="Designer">MakerDock examples</metadata><resources><object id="1" type="model"><mesh><vertices>{vs}</vertices><triangles>{ts}</triangles></mesh></object></resources><build><item objectid="1"/></build></model>'
 out=io.BytesIO()
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for name,data in {'[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/><Default Extension="png" ContentType="image/png"/></Types>','_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>','3D/3dmodel.model':xml,'Metadata/plate_1.png':thumb}.items():
   zi=zipfile.ZipInfo(name,(2026,1,1,0,0,0));zi.compress_type=zipfile.ZIP_DEFLATED;z.writestr(zi,data)
 return out.getvalue()

def create(root,locale):
 root=Path(root)
 if root.exists():raise SystemExit('Refusing to overwrite an existing directory: '+str(root))
 (root/'Files').mkdir(parents=True);(root/'Previews').mkdir();names,cats,designer,note,run_note,profile=LOCALES[locale]
 catids=[str(uuid.uuid5(uuid.NAMESPACE_DNS,'makerdock-demo-'+str(i))).upper() for i in range(3)];items=[]
 for i,faces in enumerate(geometries()):
  thumb=render(faces,COLORS[i]);data=archive(names[i],faces,thumb);key=hashlib.sha256(data).hexdigest();(root/'Files'/f'{key}.3mf').write_bytes(data)
  preview=f'Previews/{key}.png';(root/preview).write_bytes(thumb)
  filament={'id':'1','name':'Matte PLA' if i!=1 else 'Basic PETG','material':'PLA' if i!=1 else 'PETG','color':COLORS[i],'grams':[68.4,18.2,51.6,39.5,62.1,12.8][i]}
  seconds=[6840,2040,8700,4500,9360,1620][i]
  plates=[]
  for n in range(3 if i==0 else 1):
   mesh=faces if n==0 else tray(w=40,d=40,h=9) if n==1 else box(0,0,0,60,4,17)
   pp=f'Previews/{key}-plate{n+1}.png';(root/pp).write_bytes(render(mesh,COLORS[i],True))
   plates.append(dict(id=str(n+1),name=f'Plate {n+1}',thumbnailPath=pp,estimatedSeconds=seconds if n==0 else 1620 if n==1 else 900,weightGrams=filament['grams'] if n==0 else 12,filaments=[dict(filament,grams=filament['grams'] if n==0 else 12)]))
  date=f'2026-09-{8-i:02d}T01:00:00Z'
  runs=[] if i not in (2,4) else [dict(id=str(uuid.uuid4()),date='2026-09-07T08:00:00Z',status='completed',source='manual',note=run_note,durationSeconds=seconds,durationSource='file',filaments=[filament])]
  items.append(dict(id=key,title=names[i],filename=names[i]+'.3mf',filePath=f'Files/{key}.3mf',thumbnailPath=preview,sourcePaths=[],designer=designer,profileTitle=profile,materials=[filament['material']],printerModel='Bambu Lab A1',plates=plates,hasGCode=False,importedAt=date,fileAddedAt=date,tags=[],favorite=i in (0,2),note=note if i==0 else '',printRuns=runs,filaments=[filament],categoryID=catids[0 if i<3 else 2 if i==4 else 1]))
 (root/'index.json').write_text(json.dumps(dict(schemaVersion=1,items=items,categories=[dict(id=k,name=n) for k,n in zip(catids,cats)]),ensure_ascii=False,indent=2))
 (root/'preferences.json').write_text(json.dumps(dict(folders=[],studioPath='/Applications/BambuStudio.app',automaticScan=False,completedMoveMode='library',archivePath=str(root/'StudioInbox'),printerSetupInitialized=True)))
 print(root)
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory');p.add_argument('--locale',choices=LOCALES,default='en');a=p.parse_args();create(a.directory,a.locale)
