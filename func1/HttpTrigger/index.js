const axios = require('axios');

module.exports = async function (context, req) {
    context.log('JavaScript HTTP trigger function processed a request.');
    const privurlhost = req.headers.host.replace(".azurewebsites", "priv.azurewebsites")
    context.log(`preaxios: https://${privurlhost}/api/httptrigger`)
    const res = await axios.get(`https://${privurlhost}/api/httptrigger`);
    context.log(res.data)
    context.log("postaxios")
    context.res = {
        // status: 200, /* Defaults to 200 */
        body: res.data
    };
}