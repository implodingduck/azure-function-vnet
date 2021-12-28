const axios = require('axios');

module.exports = async function (context, req) {
    context.log('JavaScript HTTP trigger function processed a request.');
    context.log(JSON.stringify(req))
    context.log("preaxios")
    const res = await axios.get('https://funcvnetntb4g10spriv.azurewebsites.net/api/httptrigger');
    context.log(res.data)
    context.log("postaxios")
    context.res = {
        // status: 200, /* Defaults to 200 */
        body: res.data
    };
}