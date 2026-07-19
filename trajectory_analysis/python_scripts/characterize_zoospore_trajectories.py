#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,math,xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
import numpy as np

@dataclass
class Track:
    track_id:int; source_xml:str; frames:np.ndarray; xy:np.ndarray
    @property
    def n_spots(self): return int(self.xy.shape[0])

def lname(tag): return tag.rsplit('}',1)[-1]
def write_csv(path,rows,fields=None):
    path.parent.mkdir(parents=True,exist_ok=True)
    fields=fields or (list(rows[0].keys()) if rows else [])
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore'); w.writeheader(); w.writerows(rows)
def wrap(a): return (np.asarray(a)+180)%360-180
def sdiv(a,b): return float(a/b) if b and np.isfinite(b) else math.nan

def read_simple(path,scale,min_spots):
    root=ET.parse(path).getroot(); out=[]
    for p in [e for e in root.iter() if lname(e.tag)=='particle']:
        ds=[e for e in p if lname(e.tag)=='detection']; ds.sort(key=lambda d:int(float(d.attrib['t'])))
        if len(ds)<=min_spots: continue
        fr=np.array([int(float(d.attrib['t'])) for d in ds]); xy=np.array([[float(d.attrib['x'])*scale,float(d.attrib['y'])*scale] for d in ds])
        keep=np.ones(fr.size,dtype=bool); keep[1:]=fr[1:]!=fr[:-1]; fr,xy=fr[keep],xy[keep]
        if len(fr)>min_spots: out.append((fr,xy))
    return out

def read_trackmate(path,scale,min_spots):
    root=ET.parse(path).getroot(); spots={}
    for e in root.iter():
        if lname(e.tag)=='Spot' and 'ID' in e.attrib:
            a=e.attrib; sid=int(float(a['ID'])); fr=int(float(a.get('FRAME',a.get('POSITION_T',0)))); spots[sid]=(fr,float(a['POSITION_X'])*scale,float(a['POSITION_Y'])*scale)
    visible={int(float(e.attrib['TRACK_ID'])) for e in root.iter() if lname(e.tag)=='TrackID' and 'TRACK_ID' in e.attrib}
    out=[]
    for e in root.iter():
        if lname(e.tag)!='Track' or 'TRACK_ID' not in e.attrib: continue
        tid=int(float(e.attrib['TRACK_ID']))
        if visible and tid not in visible: continue
        ids=set()
        for ed in e:
            if lname(ed.tag)=='Edge':
                ids.add(int(float(ed.attrib['SPOT_SOURCE_ID']))); ids.add(int(float(ed.attrib['SPOT_TARGET_ID'])))
        pts=sorted((spots[i] for i in ids if i in spots),key=lambda p:p[0])
        if len(pts)<=min_spots: continue
        fr=np.array([p[0] for p in pts]); xy=np.array([[p[1],p[2]] for p in pts])
        keep=np.ones(fr.size,dtype=bool); keep[1:]=fr[1:]!=fr[:-1]; fr,xy=fr[keep],xy[keep]
        if len(fr)>min_spots: out.append((fr,xy))
    return out

def read_xml(path,scale,min_spots):
    root=ET.parse(path).getroot()
    if any(lname(e.tag)=='particle' for e in root.iter()): return read_simple(path,scale,min_spots)
    if any(lname(e.tag)=='Track' and 'TRACK_ID' in e.attrib for e in root.iter()): return read_trackmate(path,scale,min_spots)
    raise ValueError(f'Unsupported XML structure: {path}')

def compute(tracks,dt,unit,turn_thr,max_lag):
    tr,st,tu=[],[],[]; heads={}
    sk=f'speed_{unit}_per_s'; dk=f'distance_{unit}'; pk=f'path_length_{unit}'; nk=f'net_displacement_{unit}'
    for t in tracks:
        fr,xy=t.frames,t.xy; dxy=xy[1:]-xy[:-1]; dfr=np.diff(fr)*dt; dist=np.linalg.norm(dxy,axis=1)
        sp=np.divide(dist,dfr,out=np.full_like(dist,np.nan,dtype=float),where=dfr>0); hd=np.degrees(np.arctan2(dxy[:,1],dxy[:,0])); heads[t.track_id]=hd
        for i in range(len(dist)):
            st.append({'track_id':t.track_id,'source_xml':t.source_xml,'step_index':i+1,'frame_start':int(fr[i]),'frame_end':int(fr[i+1]),'dt_s':float(dfr[i]),f'x_start_{unit}':float(xy[i,0]),f'y_start_{unit}':float(xy[i,1]),f'x_end_{unit}':float(xy[i+1,0]),f'y_end_{unit}':float(xy[i+1,1]),f'dx_{unit}':float(dxy[i,0]),f'dy_{unit}':float(dxy[i,1]),dk:float(dist[i]),sk:float(sp[i]),'heading_deg':float(hd[i])})
        nturn=0
        for i in range(len(dist)-1):
            ang=float(wrap(hd[i+1]-hd[i])); aa=abs(ang); nturn+=int(aa>=turn_thr); ds=float(sp[i+1]-sp[i]); mdt=float((dfr[i]+dfr[i+1])/2); acc=ds/mdt if mdt>0 else math.nan
            tu.append({'track_id':t.track_id,'source_xml':t.source_xml,'turn_index':i+1,'frame':int(fr[i+1]),'heading_before_deg':float(hd[i]),'heading_after_deg':float(hd[i+1]),'turn_angle_deg':ang,'abs_turn_angle_deg':aa,f'speed_before_{unit}_per_s':float(sp[i]),f'speed_after_{unit}_per_s':float(sp[i+1]),f'delta_speed_{unit}_per_s':ds,f'acceleration_{unit}_per_s2':acc,f'absolute_acceleration_{unit}_per_s2':abs(acc),'is_direction_change':int(aa>=turn_thr)})
        path=float(dist.sum()); net=float(np.linalg.norm(xy[-1]-xy[0])); dur=float((fr[-1]-fr[0])*dt)
        tr.append({'track_id':t.track_id,'source_xml':t.source_xml,'n_spots':t.n_spots,'n_steps':len(dist),'duration_s':dur,pk:path,nk:net,'straightness':sdiv(net,path),'tortuosity':sdiv(path,net),f'mean_speed_{unit}_per_s':float(np.nanmean(sp)),f'median_speed_{unit}_per_s':float(np.nanmedian(sp)),f'max_speed_{unit}_per_s':float(np.nanmax(sp)),'direction_change_count':nturn,'direction_change_frequency_per_s':sdiv(nturn,dur)})
    msd=[]
    for lag in range(1,max_lag+1):
        vals=[]
        for t in tracks:
            if t.n_spots>lag: vals.extend(np.sum((t.xy[lag:]-t.xy[:-lag])**2,axis=1).tolist())
        v=np.asarray(vals,float); v=v[np.isfinite(v)]
        if v.size: msd.append({'lag_frames':lag,'lag_s':lag*dt,f'msd_{unit}2':float(v.mean()),f'median_squared_displacement_{unit}2':float(np.median(v)),'n_pairs':int(v.size)})
    dac=[]
    for lag in range(1,max_lag+1):
        vals=[]
        for h in heads.values():
            if h.size>lag: vals.extend(np.cos(np.radians(h[lag:])-np.radians(h[:-lag])).tolist())
        v=np.asarray(vals,float); v=v[np.isfinite(v)]
        if v.size: dac.append({'lag_steps':lag,'lag_s':lag*dt,'direction_autocorrelation':float(v.mean()),'n_pairs':int(v.size)})
    return tr,st,tu,msd,dac

def main():
    p=argparse.ArgumentParser(); p.add_argument('xml_source',type=Path); p.add_argument('-o','--outdir',type=Path,default=Path('zoospore_metrics')); p.add_argument('--dt',type=float,default=0.22); p.add_argument('--coord-scale',type=float,default=1.0); p.add_argument('--unit',default='micron'); p.add_argument('--min-spots',type=int,default=10); p.add_argument('--direction-threshold-deg',type=float,default=30.0); p.add_argument('--max-lag',type=int,default=25); a=p.parse_args(); a.outdir.mkdir(parents=True,exist_ok=True)
    xmls=sorted(a.xml_source.glob('*.xml')) if a.xml_source.is_dir() else [a.xml_source]
    if not xmls: raise ValueError('No XML files found')
    tracks=[]; src=[]; nid=1
    for x in xmls:
        loc=read_xml(x,a.coord_scale,a.min_spots); first=nid
        for fr,xy in loc: tracks.append(Track(nid,x.name,fr,xy)); nid+=1
        src.append({'source_xml':x.name,'n_tracks_retained':len(loc),'first_global_track_id':first if loc else '','last_global_track_id':nid-1 if loc else '','n_spots_retained':sum(len(fr) for fr,_ in loc)})
        print(f'{x.name}: {len(loc)} tracks')
    tr,st,tu,msd,dac=compute(tracks,a.dt,a.unit,a.direction_threshold_deg,a.max_lag)
    write_csv(a.outdir/'track_metrics.csv',tr); write_csv(a.outdir/'step_metrics.csv',st); write_csv(a.outdir/'turn_metrics.csv',tu); write_csv(a.outdir/'msd.csv',msd); write_csv(a.outdir/'direction_autocorrelation.csv',dac); write_csv(a.outdir/'source_xml_summary.csv',src)
    write_csv(a.outdir/'summary.csv',[{'n_xml_files':len(xmls),'n_tracks':len(tr),'n_steps':len(st),'n_turns':len(tu),'dt_s':a.dt,'unit':a.unit,'direction_threshold_deg':a.direction_threshold_deg}])
    print(f'Tables written to: {a.outdir}')
if __name__=='__main__': main()
