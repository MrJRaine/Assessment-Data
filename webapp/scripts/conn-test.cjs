// TEMP diagnostic — standalone Fabric SQL connection test (not committed).
const sql = require('mssql')

const cfg = {
  server: process.env.FABRIC_SQL_SERVER,
  database: process.env.FABRIC_SQL_DATABASE,
  port: 1433,
  connectionTimeout: 30000,
  options: { encrypt: true, trustServerCertificate: true },
  authentication: {
    type: 'azure-active-directory-service-principal-secret',
    options: {
      clientId: process.env.ENTRA_CLIENT_ID,
      clientSecret: process.env.ENTRA_CLIENT_SECRET,
      tenantId: process.env.ENTRA_TENANT_ID,
    },
  },
}

;(async () => {
  console.log('node', process.version, '-> connecting to', cfg.server)
  try {
    const pool = await new sql.ConnectionPool(cfg).connect()
    const r = await pool.request().query('SELECT DB_NAME() AS db, CAST(CURRENT_USER AS VARCHAR(200)) AS who')
    console.log('OK', JSON.stringify(r.recordset[0]))
    await pool.close()
  } catch (e) {
    console.log('FAIL code=', e.code, 'msg=', e.message)
    if (e.originalError) console.log('ORIG', e.originalError.message || String(e.originalError))
    console.log('STACK', (e.stack || '').split('\n').slice(0, 4).join(' | '))
  }
})()
