#!/usr/bin/env python3
from __future__ import annotations
import tol_colors as tc
import argparse,csv,math
from collections import defaultdict
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np

def read_csv(path):
    with Path(path).open(newline='') as f: return list(csv.DictReader(f))
def write_csv(path,rows,fields=None):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True); fields=fields or (list(rows[0].keys()) if rows else [])
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore'); w.writeheader(); w.writerows(rows)
def num(r,k):
    try:return float(r[k])
    except:return math.nan
def finite(vals):
    a=np.asarray(list(vals),float); return a[np.isfinite(a)]
def find(cols,prefix):
    m=[c for c in cols if c.startswith(prefix)]
    if len(m)!=1: raise ValueError(f'Expected one column beginning with {prefix}: {m}')
    return m[0]
def save(fig,path,dpi):
    Path(path).parent.mkdir(parents=True,exist_ok=True); fig.savefig(path,dpi=dpi,bbox_inches='tight'); plt.close(fig)
def hist(vals,path,title,xlabel,bins,dpi,vline=None):
    vals=np.asarray(vals,float); vals=vals[np.isfinite(vals)]
    if not vals.size:return
    fig,ax=plt.subplots(figsize=(7,4.5)); ax.hist(vals,bins=bins,color='0.82',edgecolor='0.30',linewidth=.6); ax.axvline(np.median(vals),color='0.05',ls='--',lw=1)
    if vline is not None: ax.axvline(vline,color='0.05',ls=':',lw=1.5)
    ax.set(title=title,xlabel=xlabel,ylabel='Count'); ax.text(.98,.95,f'n = {vals.size}\nmedian = {np.median(vals):.3g}',transform=ax.transAxes,ha='right',va='top'); save(fig,path,dpi)
def otsu(vals,bins=256):
    vals=vals[np.isfinite(vals)]; c,e=np.histogram(vals,bins=bins); x=(e[:-1]+e[1:])/2; c=c.astype(float); wl=np.cumsum(c); wr=c.sum()-wl; sl=np.cumsum(c*x); total=np.sum(c*x); ok=(wl>0)&(wr>0); ml=np.zeros_like(x); mr=np.zeros_like(x); ml[ok]=sl[ok]/wl[ok]; mr[ok]=(total-sl[ok])/wr[ok]; score=wl*wr*(ml-mr)**2; score[~ok]=-np.inf; return float(x[np.argmax(score)])
def groups(rows):
    d=defaultdict(list)
    for r in rows:d[int(float(r['track_id']))].append(r)
    for g in d.values():g.sort(key=lambda r:int(float(r['step_index'])))
    return d
def pearson(x,y):
    ok=np.isfinite(x)&np.isfinite(y); x,y=x[ok],y[ok]
    return float(np.corrcoef(x,y)[0,1]) if x.size>=3 and np.std(x)>0 and np.std(y)>0 else math.nan
def binned(x,y,n):
    ok=np.isfinite(x)&np.isfinite(y); x,y=x[ok],y[ok]
    if not x.size:return []
    e=np.linspace(x.min(),x.max(),n+1); idx=np.digitize(x,e[1:-1]); out=[]
    for i in range(n):
        v=y[idx==i]
        if v.size: out.append({'x_bin_start':e[i],'x_bin_end':e[i+1],'x_bin_center':(e[i]+e[i+1])/2,'n':int(v.size),'mean_y':float(v.mean()),'median_y':float(np.median(v)),'q25_y':float(np.percentile(v,25)),'q75_y':float(np.percentile(v,75))})
    return out

def lowess(x,y,frac=0.20,n_points=250,robust_iterations=2):
    """Return a robust LOWESS curve without requiring statsmodels."""
    x=np.asarray(x,float); y=np.asarray(y,float)
    ok=np.isfinite(x)&np.isfinite(y); x,y=x[ok],y[ok]
    if x.size<3:return np.asarray([]),np.asarray([])
    order=np.argsort(x); x,y=x[order],y[order]
    grid=np.linspace(x.min(),x.max(),n_points)
    span=max(3,min(x.size,int(math.ceil(frac*x.size))))
    robust=np.ones(x.size,float)
    def fit_at(x0,robust_weights):
        distance=np.abs(x-x0)
        neighbours=np.argpartition(distance,span-1)[:span]
        dmax=distance[neighbours].max()
        if dmax<=0:return float(np.average(y[neighbours],weights=robust_weights[neighbours]))
        u=distance[neighbours]/dmax
        tricube=(1-u**3)**3
        weights=tricube*robust_weights[neighbours]
        X=np.column_stack((np.ones(neighbours.size),x[neighbours]-x0))
        sw=np.sqrt(weights)
        beta=np.linalg.lstsq(X*sw[:,None],y[neighbours]*sw,rcond=None)[0]
        return float(beta[0])
    for iteration in range(max(0,robust_iterations)+1):
        fitted=np.asarray([fit_at(x0,robust) for x0 in x])
        if iteration==robust_iterations:break
        residuals=y-fitted
        scale=np.median(np.abs(residuals))
        if not np.isfinite(scale) or scale<=0:break
        u=np.clip(residuals/(6*scale),-1,1)
        robust=(1-u**2)**2
        robust[np.abs(residuals)>=6*scale]=0
    smooth=np.asarray([fit_at(x0,robust) for x0 in grid])
    return grid,smooth

def scatter_with_lowess(ax,x,y,frac=0.20,max_points=50000,seed=42,point_size=4,point_alpha=0.12):
    """Draw light-grey observations and a black robust LOWESS curve."""
    x=np.asarray(x,float); y=np.asarray(y,float)
    ok=np.isfinite(x)&np.isfinite(y); x,y=x[ok],y[ok]
    if x.size==0:return
    if x.size>max_points:
        idx=np.random.default_rng(seed).choice(x.size,max_points,replace=False)
        x_plot,y_plot=x[idx],y[idx]
    else:x_plot,y_plot=x,y
    ax.scatter(x_plot,y_plot,s=point_size,alpha=point_alpha,color='0.72',edgecolors='none',rasterized=True)
    sx,sy=lowess(x,y,frac=frac)
    if sx.size:ax.plot(sx,sy,color='black',lw=2.2,zorder=3)

def main():
    p=argparse.ArgumentParser(); p.add_argument('metrics_dir',type=Path); p.add_argument('-o','--outdir',type=Path,default=None); p.add_argument('--state-speed-threshold',type=float,default=None); p.add_argument('--bins',type=int,default=50); p.add_argument('--coupling-bins',type=int,default=20); p.add_argument('--smooth-frac',type=float,default=0.20,help='LOWESS smoothing fraction for relationship plots (default: 0.20)'); p.add_argument('--dpi',type=int,default=300); a=p.parse_args()
    out=a.outdir or a.metrics_dir/'grouped_analysis'; c1=out/'I_motion_states'; c2=out/'II_kinematics'; c3=out/'III_steering_behaviour'; c4=out/'IV_variable_coupling'; c5=out/'V_spatial_exploration'
    for d in (c1,c2,c3,c4,c5):d.mkdir(parents=True,exist_ok=True)
    st=read_csv(a.metrics_dir/'step_metrics.csv'); tu=read_csv(a.metrics_dir/'turn_metrics.csv'); tr=read_csv(a.metrics_dir/'track_metrics.csv'); msd=read_csv(a.metrics_dir/'msd.csv'); dac=read_csv(a.metrics_dir/'direction_autocorrelation.csv')
    sk=find(st[0].keys(),'speed_'); dk=find(st[0].keys(),'distance_'); ak=find(tu[0].keys(),'acceleration_'); aak=find(tu[0].keys(),'absolute_acceleration_'); sbk=find(tu[0].keys(),'speed_before_'); msk=find(tr[0].keys(),'mean_speed_'); pk=find(tr[0].keys(),'path_length_'); nk=find(tr[0].keys(),'net_displacement_'); mk=find(msd[0].keys(),'msd_'); unit=dk.removeprefix('distance_')
    sp=finite(num(r,sk) for r in st); thr=a.state_speed_threshold if a.state_speed_threshold is not None else otsu(sp); method='manual' if a.state_speed_threshold is not None else 'Otsu'; gs=groups(st)
    # I Motion states
    hist(sp,c1/'01_run_stop_threshold.png','Instantaneous speed and RUN/STOP threshold',f'Speed ({unit}/s)',a.bins,a.dpi,thr); write_csv(c1/'01_run_stop_threshold.csv',[{'threshold':thr,'method':method,'unit':f'{unit}/s'}])
    episodes=[]; tc={'STOP_STOP':0,'STOP_RUN':0,'RUN_STOP':0,'RUN_RUN':0}; eid=1
    for tid,rows in gs.items():
        use=[r for r in rows if np.isfinite(num(r,sk))]; states=['RUN' if num(r,sk)>=thr else 'STOP' for r in use]
        for x,y in zip(states[:-1],states[1:]):tc[f'{x}_{y}']+=1
        i=0
        while i<len(use):
            s=states[i]; j=i+1
            while j<len(use) and states[j]==s:j+=1
            b=use[i:j]; episodes.append({'episode_id':eid,'track_id':tid,'state':s,'start_frame':int(float(b[0]['frame_start'])),'end_frame':int(float(b[-1]['frame_end'])),'n_steps':len(b),'duration_s':sum(num(r,'dt_s') for r in b),f'length_{unit}':sum(num(r,dk) for r in b),f'mean_speed_{unit}_per_s':float(np.mean([num(r,sk) for r in b]))}); eid+=1; i=j
    write_csv(c1/'motion_episodes.csv',episodes); ss,sr,rs,rr=tc['STOP_STOP'],tc['STOP_RUN'],tc['RUN_STOP'],tc['RUN_RUN']; trans=[{'from_state':'STOP','to_state':'STOP','count':ss,'probability':ss/(ss+sr) if ss+sr else math.nan},{'from_state':'STOP','to_state':'RUN','count':sr,'probability':sr/(ss+sr) if ss+sr else math.nan},{'from_state':'RUN','to_state':'STOP','count':rs,'probability':rs/(rs+rr) if rs+rr else math.nan},{'from_state':'RUN','to_state':'RUN','count':rr,'probability':rr/(rs+rr) if rs+rr else math.nan}]; write_csv(c1/'02_transition_probabilities.csv',trans)
    fig,ax=plt.subplots(figsize=(6.2,4.5)); ax.bar(['STOP→STOP','STOP→RUN','RUN→STOP','RUN→RUN'],[r['probability'] for r in trans],color='0.82',edgecolor='0.30'); ax.set_ylim(0,1); ax.set(title='Motion-state transition probabilities',ylabel='Probability per step'); ax.tick_params(axis='x',rotation=25); save(fig,c1/'02_transition_probabilities.png',a.dpi)
    runs=[r for r in episodes if r['state']=='RUN']; stops=[r for r in episodes if r['state']=='STOP']; hist([r['duration_s'] for r in runs],c1/'03_run_duration.png','RUN episode duration','Duration (s)',a.bins,a.dpi); hist([r['duration_s'] for r in stops],c1/'04_stop_duration.png','STOP episode duration','Duration (s)',a.bins,a.dpi); hist([r[f'length_{unit}'] for r in runs],c1/'05_run_length.png','RUN episode length',f'Length ({unit})',a.bins,a.dpi); hist([r[f'length_{unit}'] for r in stops],c1/'06_stop_length.png','STOP episode length',f'Length ({unit})',a.bins,a.dpi)
    # II Kinematics
    hist(sp,c2/'01_speed_distribution.png','Instantaneous speed distribution',f'Speed ({unit}/s)',a.bins,a.dpi); write_csv(c2/'01_speed_distribution.csv',[{sk:v} for v in sp]); sa=finite(num(r,ak) for r in tu); aa=finite(num(r,aak) for r in tu); hist(sa,c2/'02_signed_acceleration.png','Signed acceleration distribution',f'Acceleration ({unit}/s²)',a.bins,a.dpi); hist(aa,c2/'03_absolute_acceleration.png','Absolute acceleration distribution',f'Absolute acceleration ({unit}/s²)',a.bins,a.dpi); write_csv(c2/'accelerations.csv',[{'track_id':r['track_id'],'frame':r['frame'],ak:num(r,ak),aak:num(r,aak)} for r in tu])
    maxlag=max(int(float(r['lag_steps'])) for r in dac) if dac else 25; dt=float(st[0]['dt_s']); sac=[]
    for lag in range(1,maxlag+1):
        l=[]; rr2=[]
        for rows in gs.values():
            v=np.asarray([num(r,sk) for r in rows]);
            if len(v)<=lag:continue
            x,y=v[:-lag],v[lag:]; ok=np.isfinite(x)&np.isfinite(y); l.extend(x[ok]); rr2.extend(y[ok])
        sac.append({'lag_steps':lag,'lag_s':lag*dt,'speed_autocorrelation':pearson(np.asarray(l),np.asarray(rr2)),'n_pairs':len(l)})
    write_csv(c2/'04_speed_autocorrelation.csv',sac); fig,ax=plt.subplots(figsize=(6.5,4.5)); ax.plot([r['lag_s'] for r in sac],[r['speed_autocorrelation'] for r in sac],color='0.1',marker='o',ms=3); ax.axhline(0,color='0.5',lw=.8); ax.set(title='Speed autocorrelation',xlabel='Lag (s)',ylabel='Pearson correlation'); save(fig,c2/'04_speed_autocorrelation.png',a.dpi)
    # III Steering
    sangle=finite(num(r,'turn_angle_deg') for r in tu); aangle=finite(num(r,'abs_turn_angle_deg') for r in tu); hist(sangle,c3/'01_signed_turn_angle.png','Signed turning-angle distribution','Turning angle (degrees)',72,a.dpi); hist(aangle,c3/'02_absolute_turn_angle.png','Absolute turning-angle distribution','Absolute turning angle (degrees)',36,a.dpi); write_csv(c3/'turning_angles.csv',[{'track_id':r['track_id'],'frame':r['frame'],'turn_angle_deg':num(r,'turn_angle_deg'),'abs_turn_angle_deg':num(r,'abs_turn_angle_deg')} for r in tu])
    x=np.asarray([num(r,sbk) for r in tu]); y=np.asarray([num(r,'abs_turn_angle_deg') for r in tu]); bs=binned(x,y,a.coupling_bins); write_csv(c3/'03_speed_vs_turn_angle_binned.csv',bs); fig,ax=plt.subplots(figsize=(6.5,5))
    scatter_with_lowess(ax,x,y,frac=a.smooth_frac)
    ax.set(title='Speed versus turning angle',xlabel=f'Speed before turn ({unit}/s)',ylabel='Absolute turning angle (degrees)'); save(fig,c3/'03_speed_vs_turn_angle.png',a.dpi)
    write_csv(c3/'04_direction_autocorrelation.csv',dac); fig,ax=plt.subplots(figsize=(6.5,4.5)); ax.plot([num(r,'lag_s') for r in dac],[num(r,'direction_autocorrelation') for r in dac],color='0.1',marker='o',ms=3); ax.axhline(0,color='0.5',lw=.8); ax.set(title='Direction autocorrelation',xlabel='Lag (s)',ylabel='Mean cos(Δheading)'); save(fig,c3/'04_direction_autocorrelation.png',a.dpi)
    # IV Coupling
    write_csv(c4/'01_speed_turn_pairs.csv',[{sbk:num(r,sbk),'abs_turn_angle_deg':num(r,'abs_turn_angle_deg')} for r in tu]); write_csv(c4/'01_speed_turn_binned.csv',bs)
    xa=np.asarray([num(r,sbk) for r in tu]); ya=np.asarray([num(r,ak) for r in tu]); bsa=binned(xa,ya,a.coupling_bins); write_csv(c4/'02_speed_acceleration_pairs.csv',[{sbk:num(r,sbk),ak:num(r,ak)} for r in tu]); write_csv(c4/'02_speed_acceleration_binned.csv',bsa); fig,ax=plt.subplots(figsize=(6.5,5))
    scatter_with_lowess(ax,xa,ya,frac=a.smooth_frac)
    ax.axhline(0,color='0.5',lw=.8); ax.set(title='Speed versus acceleration',xlabel=f'Speed before transition ({unit}/s)',ylabel=f'Acceleration ({unit}/s²)'); save(fig,c4/'02_speed_acceleration.png',a.dpi)
    xp=np.asarray([num(r,msk) for r in tr]); yp=np.asarray([num(r,'straightness') for r in tr]); bsp=binned(xp,yp,a.coupling_bins); write_csv(c4/'03_persistence_speed_pairs.csv',[{msk:num(r,msk),'straightness':num(r,'straightness')} for r in tr]); write_csv(c4/'03_persistence_speed_binned.csv',bsp); fig,ax=plt.subplots(figsize=(6.5,5))
    scatter_with_lowess(ax,xp,yp,frac=a.smooth_frac,point_size=6,point_alpha=0.18)
    ax.set(title='Straightness versus mean speed',xlabel=f'Mean speed ({unit}/s)',ylabel='Straightness'); save(fig,c4/'03_persistence_speed.png',a.dpi); write_csv(c4/'coupling_summary.csv',[{'relationship':'speed_vs_abs_turn','pearson_r':pearson(x,y),'n':int(np.sum(np.isfinite(x)&np.isfinite(y)))},{'relationship':'speed_vs_acceleration','pearson_r':pearson(xa,ya),'n':int(np.sum(np.isfinite(xa)&np.isfinite(ya)))},{'relationship':'mean_speed_vs_straightness','pearson_r':pearson(xp,yp),'n':int(np.sum(np.isfinite(xp)&np.isfinite(yp)))}])
    # V Spatial exploration
    write_csv(c5/'01_msd.csv',msd); fig,ax=plt.subplots(figsize=(6.5,4.5)); ax.plot([num(r,'lag_s') for r in msd],[num(r,mk) for r in msd],color='0.1',marker='o',ms=3); ax.set(title='Mean squared displacement',xlabel='Lag (s)',ylabel=f'MSD ({unit}²)'); save(fig,c5/'01_msd.png',a.dpi)
    straight=finite(num(r,'straightness') for r in tr); tort=finite(num(r,'tortuosity') for r in tr); net=finite(num(r,nk) for r in tr); hist(straight,c5/'02_straightness.png','Trajectory straightness','Net displacement / path length',40,a.dpi); hist(tort,c5/'03_tortuosity.png','Trajectory tortuosity','Path length / net displacement',a.bins,a.dpi); hist(net,c5/'04_net_displacement.png','Net displacement',f'Net displacement ({unit})',a.bins,a.dpi); write_csv(c5/'track_spatial_metrics.csv',[{'track_id':r['track_id'],pk:num(r,pk),nk:num(r,nk),'straightness':num(r,'straightness'),'tortuosity':num(r,'tortuosity')} for r in tr])
    write_csv(out/'analysis_summary.csv',[{'run_stop_threshold':thr,'threshold_method':method,'n_tracks':len(tr),'n_steps':len(st),'n_turns':len(tu),'n_run_episodes':len(runs),'n_stop_episodes':len(stops),'unit':unit}]); print(f'Grouped analysis written to: {out}')
if __name__=='__main__': main()
