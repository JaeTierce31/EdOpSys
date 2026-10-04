import type { QKernelService } from './q-service.js';
export type TransportRequest={method:string;path:string;body?:any};
export type TransportResponse={status:number;body:any};
export function createTransportHandler(service:QKernelService){
  return async function handle(req:TransportRequest):Promise<TransportResponse>{
    try{
      if(req.method==='POST'&&req.path==='/v1/clp001/transitions') return {status:200,body:await service.executeTransition(req.body)};
      if(req.method==='POST'&&req.path==='/v1/clp001/eligibility') return {status:200,body:service.evaluateWorker(req.body.worker,req.body.context)};
      const state=req.path.match(/^\/v1\/clp001\/cases\/([^/]+)\/state$/);
      if(req.method==='GET'&&state) return {status:200,body:{correlation_id:state[1],state:await service.caseState(state[1])}};
      const replay=req.path.match(/^\/v1\/clp001\/cases\/([^/]+)\/replay$/);
      if(req.method==='GET'&&replay) return {status:200,body:await service.replay(replay[1])};
      const envelope=req.path.match(/^\/v1\/clp001\/cases\/([^/]+)\/replay-envelope$/);
      if(req.method==='GET'&&envelope) return {status:200,body:await service.replayEnvelope(envelope[1])};
      return {status:404,body:{error:'NOT_FOUND'}};
    }catch(err){return {status:409,body:{error:err instanceof Error?err.message:String(err)}};}
  };
}
