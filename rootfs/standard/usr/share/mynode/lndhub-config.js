let config = {
    enableUpdateDescribeGraph: false,
    postRateLimit: 100,
    rateLimit: 200,
    //bitcoind: {
    //  rpc: 'http://mynode:bolt@127.0.0.1:8332/wallet/wallet.dat',
    //},
    redis: {
      port: 6379,
      host: '127.0.0.1',
      family: 4,
      password: '',
      db: 0,
    },
    lnd: {
      url: '127.0.0.1:10009',
      password: '',
    },
  };
  
  if (process.env.CONFIG) {
    console.log('using config from env');
    config = JSON.parse(process.env.CONFIG);
  }
  
  module.exports = config;