# RUM application_id / client_token per tenant, for syncing into each tenant's
# env vars. Note that client_token is not a secret, regardless of its name.

output "rum_credentials" {
  description = "Map of tenant slug -> { application_id, client_token } for the tenant's browser RUM application."
  value = {
    dnfsb    = { application_id = module.dnfsb.rum_application_id, client_token = module.dnfsb.rum_client_token }
    doj      = { application_id = module.doj.rum_application_id, client_token = module.doj.rum_client_token }
    faa      = { application_id = module.faa.rum_application_id, client_token = module.faa.rum_client_token }
    ftc      = { application_id = module.ftc.rum_application_id, client_token = module.ftc.rum_client_token }
    nrc      = { application_id = module.nrc.rum_application_id, client_token = module.nrc.rum_client_token }
    ntsb     = { application_id = module.ntsb.rum_application_id, client_token = module.ntsb.rum_client_token }
    oge      = { application_id = module.oge.rum_application_id, client_token = module.oge.rum_client_token }
    ang      = { application_id = module.ang.rum_application_id, client_token = module.ang.rum_client_token }
    doc      = { application_id = module.doc.rum_application_id, client_token = module.doc.rum_client_token }
    doi      = { application_id = module.doi.rum_application_id, client_token = module.doi.rum_client_token }
    doli     = { application_id = module.doli.rum_application_id, client_token = module.doli.rum_client_token }
    dot      = { application_id = module.dot.rum_application_id, client_token = module.dot.rum_client_token }
    ed       = { application_id = module.ed.rum_application_id, client_token = module.ed.rum_client_token }
    fhfa     = { application_id = module.fhfa.rum_application_id, client_token = module.fhfa.rum_client_token }
    gsa      = { application_id = module.gsa.rum_application_id, client_token = module.gsa.rum_client_token }
    hhs      = { application_id = module.hhs.rum_application_id, client_token = module.hhs.rum_client_token }
    hud      = { application_id = module.hud.rum_application_id, client_token = module.hud.rum_client_token }
    ncua     = { application_id = module.ncua.rum_application_id, client_token = module.ncua.rum_client_token }
    opm      = { application_id = module.opm.rum_application_id, client_token = module.opm.rum_client_token }
    pc       = { application_id = module.pc.rum_application_id, client_token = module.pc.rum_client_token }
    sss      = { application_id = module.sss.rum_application_id, client_token = module.sss.rum_client_token }
    stateoig = { application_id = module.stateoig.rum_application_id, client_token = module.stateoig.rum_client_token }
    usda     = { application_id = module.usda.rum_application_id, client_token = module.usda.rum_client_token }
    nsf      = { application_id = module.nsf.rum_application_id, client_token = module.nsf.rum_client_token }
    eeoc     = { application_id = module.eeoc.rum_application_id, client_token = module.eeoc.rum_client_token }
  }
}
